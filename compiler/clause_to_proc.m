%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 1995-2012 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

:- module check_hlds.clause_to_proc.
:- interface.

:- import_module hlds.
:- import_module hlds.hlds_clauses.
:- import_module hlds.hlds_module.
:- import_module hlds.hlds_pred.
:- import_module hlds.pred_table.

:- import_module list.
:- import_module maybe.

%-----------------------------------------------------------------------------%

    % In the hlds, we initially record the clauses for a predicate in the
    % clauses_info data structure which is part of the pred_info data
    % structure. But once the clauses have been type-checked, we want to have
    % a separate copy of each clause for each different mode of the predicate,
    % since we may end up reordering the clauses differently in different
    % modes. Here we copy the clauses from the clause_info data structure
    % into the proc_info data structure. Each clause is marked with a list
    % of the modes for which it applies, so that there can be different code
    % to implement different modes of a predicate (e.g. sort). For each mode
    % of the predicate, we select the clauses for that mode, disjoin them
    % together, and save this in the proc_info.
    %
:- pred copy_module_clauses_to_procs(list(pred_id)::in,
    module_info::in, module_info::out) is det.

:- pred copy_clauses_to_proc(proc_id::in, clauses_info::in,
    proc_info::in, proc_info::out) is det.

    % Before copying the clauses to the procs, we need to add
    % a default mode of `:- mode foo(in, in, ..., in) = out is det.'
    % for functions that don't have an explicit mode declaration.
    %
:- pred maybe_add_default_func_modes(list(pred_id)::in,
    pred_table::in, pred_table::out) is det.

:- pred maybe_add_default_func_mode(pred_info::in, pred_info::out,
    maybe(proc_id)::out) is det.

    % After copying the clauses to the procs, we need to transform the
    % procedures to introduce any required exists_casts..
    %
:- pred introduce_exists_casts(list(pred_id)::in, module_info::in,
    module_info::out) is det.

    % This version is used by polymorphism.m.
    %
:- pred introduce_exists_casts_proc(module_info::in, pred_info::in,
    proc_info::in, proc_info::out) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module check_hlds.mode_util.
:- import_module hlds.goal_util.
:- import_module hlds.hlds_args.
:- import_module hlds.hlds_goal.
:- import_module hlds.hlds_rtti.
:- import_module hlds.make_hlds.
:- import_module mdbcomp.
:- import_module mdbcomp.prim_data.
:- import_module parse_tree.
:- import_module parse_tree.error_util.
:- import_module parse_tree.prog_data.
:- import_module parse_tree.prog_mode.
:- import_module parse_tree.prog_type_subst.
:- import_module parse_tree.set_of_var.

:- import_module assoc_list.
:- import_module int.
:- import_module map.
:- import_module pair.
:- import_module require.
:- import_module string.
:- import_module term.
:- import_module varset.

%-----------------------------------------------------------------------------%

maybe_add_default_func_modes([], Preds, Preds).
maybe_add_default_func_modes([PredId | PredIds], Preds0, Preds) :-
    map.lookup(Preds0, PredId, PredInfo0),
    maybe_add_default_func_mode(PredInfo0, PredInfo, _),
    map.det_update(PredId, PredInfo, Preds0, Preds1),
    maybe_add_default_func_modes(PredIds, Preds1, Preds).

maybe_add_default_func_mode(PredInfo0, PredInfo, MaybeProcId) :-
    pred_info_get_procedures(PredInfo0, Procs0),
    PredOrFunc = pred_info_is_pred_or_func(PredInfo0),
    (
        % Is this a function with no modes?
        PredOrFunc = pf_function,
        map.is_empty(Procs0)
    ->
        % If so, add a default mode of
        %
        %   :- mode foo(in, in, ..., in) = out is det.
        %
        % for this function. (N.B. functions which can fail must be
        % explicitly declared as semidet.)

        PredArity = pred_info_orig_arity(PredInfo0),
        FuncArity = PredArity - 1,
        in_mode(InMode),
        out_mode(OutMode),
        list.duplicate(FuncArity, InMode, FuncArgModes),
        FuncRetMode = OutMode,
        list.append(FuncArgModes, [FuncRetMode], PredArgModes),
        Determinism = detism_det,
        pred_info_get_context(PredInfo0, Context),
        MaybePredArgLives = no,
        varset.init(InstVarSet),
        % No inst_vars in default func mode.
        % Before the simplification pass, HasParallelConj is not meaningful.
        HasParallelConj = has_no_parallel_conj,
        add_new_proc(InstVarSet, PredArity, PredArgModes, yes(PredArgModes),
            MaybePredArgLives, detism_decl_implicit, yes(Determinism),
            Context, address_is_not_taken, HasParallelConj,
            PredInfo0, PredInfo, ProcId),
        MaybeProcId = yes(ProcId)
    ;
        PredInfo = PredInfo0,
        MaybeProcId = no
    ).

copy_module_clauses_to_procs(PredIds, !ModuleInfo) :-
    module_info_get_preds(!.ModuleInfo, PredTable0),
    list.foldl(copy_pred_clauses_to_procs_if_needed, PredIds,
        PredTable0, PredTable),
    module_info_set_preds(PredTable, !ModuleInfo).

    % For each mode of the given predicate, copy the clauses relevant
    % to the mode and the current backend to the proc_info.
    %
    % This is not the only predicate in the compiler that does this task;
    % the other is polymorphism.process_proc.
    %
:- pred copy_pred_clauses_to_procs_if_needed(pred_id::in,
    pred_table::in, pred_table::out) is det.

copy_pred_clauses_to_procs_if_needed(PredId, !PredTable) :-
    map.lookup(!.PredTable, PredId, PredInfo0),
    ( should_copy_clauses_to_procs(PredInfo0) ->
        copy_clauses_to_procs(PredInfo0, PredInfo),
        map.det_update(PredId, PredInfo, !PredTable)
    ;
        true
    ).

:- pred should_copy_clauses_to_procs(pred_info::in) is semidet.

should_copy_clauses_to_procs(PredInfo) :-
    % Don't process typeclass methods, because their proc_infos
    % are generated already mode-correct.
    pred_info_get_markers(PredInfo, PredMarkers),
    \+ check_marker(PredMarkers, marker_class_method).

:- pred copy_clauses_to_procs(pred_info::in, pred_info::out) is det.

copy_clauses_to_procs(!PredInfo) :-
    pred_info_get_procedures(!.PredInfo, Procs0),
    pred_info_get_clauses_info(!.PredInfo, ClausesInfo),
    ProcIds = pred_info_all_non_imported_procids(!.PredInfo),
    copy_clauses_to_procs_2(ProcIds, ClausesInfo, Procs0, Procs),
    pred_info_set_procedures(Procs, !PredInfo).

:- pred copy_clauses_to_procs_2(list(proc_id)::in, clauses_info::in,
    proc_table::in, proc_table::out) is det.

copy_clauses_to_procs_2([], _, !Procs).
copy_clauses_to_procs_2([ProcId | ProcIds], ClausesInfo, !Procs) :-
    map.lookup(!.Procs, ProcId, Proc0),
    copy_clauses_to_proc(ProcId, ClausesInfo, Proc0, Proc),
    map.det_update(ProcId, Proc, !Procs),
    copy_clauses_to_procs_2(ProcIds, ClausesInfo, !Procs).

copy_clauses_to_proc(ProcId, ClausesInfo, !Proc) :-
    ClausesInfo = clauses_info(VarSet0, _, _, VarTypes, HeadVars,
        ClausesRep, _ItemNumbers, RttiInfo, _HaveForeignClauses),
    get_clause_list(ClausesRep, Clauses),
    select_matching_clauses(Clauses, ProcId, MatchingClauses),
    get_clause_disjuncts_and_warnings(MatchingClauses, ClausesDisjuncts,
        StateVarWarnings),
    (
        StateVarWarnings = []
        % Do not allocate a new proc_info if we do not need to.
    ;
        StateVarWarnings = [_ | _],
        proc_info_set_statevar_warnings(StateVarWarnings, !Proc)
    ),
    (
        ClausesDisjuncts = [SingleGoal],
        SingleGoal = hlds_goal(SingleExpr, _),
        (
            SingleExpr = call_foreign_proc(_, _, _, Args, ExtraArgs,
                MaybeTraceRuntimeCond, _),
            % Use the original variable names for the headvars of foreign_proc
            % clauses, not the introduced `HeadVar__n' names.
            VarSet = list.foldl(set_arg_names, Args, VarSet0),
            expect(unify(ExtraArgs, []), $module, $pred, "extra_args"),
            expect(unify(MaybeTraceRuntimeCond, no), $module, $pred,
                "trace runtime cond")
        ;
            ( SingleExpr = plain_call(_, _, _, _, _, _)
            ; SingleExpr = generic_call(_, _, _, _, _)
            ; SingleExpr = unify(_, _, _, _, _)
            ; SingleExpr = conj(_, _)
            ; SingleExpr = disj(_)
            ; SingleExpr = switch(_, _, _)
            ; SingleExpr = if_then_else(_,_,  _, _)
            ; SingleExpr = negation(_)
            ; SingleExpr = scope(_, _)
            ; SingleExpr = shorthand(_)
            ),
            VarSet = VarSet0
        ),
        Goal = SingleGoal
    ;
        % We use the context of the first clause, unless there weren't
        % any clauses at all, in which case we use the context of the
        % mode declaration.
        (
            ClausesDisjuncts = [FirstGoal, _ | _],
            FirstGoal = hlds_goal(_, FirstGoalInfo),
            Context = goal_info_get_context(FirstGoalInfo)
        ;
            ClausesDisjuncts = [],
            proc_info_get_context(!.Proc, Context)
        ),

        % Convert the list of clauses into a disjunction,
        % and construct a goal_info for the disjunction.

        VarSet = VarSet0,
        goal_info_init(GoalInfo0),
        goal_info_set_context(Context, GoalInfo0, GoalInfo1),

        % The non-local vars are just the head variables.
        NonLocalVars =
            set_of_var.list_to_set(proc_arg_vector_to_list(HeadVars)),
        goal_info_set_nonlocals(NonLocalVars, GoalInfo1, GoalInfo2),

        % The disjunction is impure/semipure if any of the disjuncts
        % is impure/semipure.
        ( contains_nonpure_goal(ClausesDisjuncts) ->
            PurityList = list.map(goal_get_purity, ClausesDisjuncts),
            Purity = list.foldl(worst_purity, PurityList, purity_pure),
            goal_info_set_purity(Purity, GoalInfo2, GoalInfo)
        ;
            GoalInfo2 = GoalInfo
        ),

        Goal = hlds_goal(disj(ClausesDisjuncts), GoalInfo)
    ),
    % XXX ARGVEC - when the proc_info is converted to use proc_arg_vectors
    % we should just pass the headvar vector in directly.
    HeadVarList = proc_arg_vector_to_list(HeadVars),
    proc_info_set_body(VarSet, VarTypes, HeadVarList, Goal, RttiInfo, !Proc).

:- pred contains_nonpure_goal(list(hlds_goal)::in) is semidet.

contains_nonpure_goal([Goal | Goals]) :-
    (
        goal_get_purity(Goal) \= purity_pure
    ;
        contains_nonpure_goal(Goals)
    ).

:- func set_arg_names(foreign_arg, prog_varset) = prog_varset.

set_arg_names(Arg, !.Vars) = !:Vars :-
    Var = foreign_arg_var(Arg),
    MaybeNameMode = foreign_arg_maybe_name_mode(Arg),
    (
        MaybeNameMode = yes(Name - _),
        varset.name_var(Var, Name, !Vars)
    ;
        MaybeNameMode = no
    ).

:- pred select_matching_clauses(list(clause)::in, proc_id::in,
    list(clause)::out) is det.

select_matching_clauses([], _, []).
select_matching_clauses([Clause | Clauses], ProcId, MatchingClauses) :-
    select_matching_clauses(Clauses, ProcId, MatchingClausesTail),
    ApplicableProcIds = Clause ^ clause_applicable_procs,
    (
        ApplicableProcIds = all_modes,
        MatchingClauses = [Clause | MatchingClausesTail]
    ;
        ApplicableProcIds = selected_modes(ProcIds),
        ( list.member(ProcId, ProcIds) ->
            MatchingClauses = [Clause | MatchingClausesTail]
        ;
            MatchingClauses = MatchingClausesTail
        )
    ).

:- pred get_clause_disjuncts_and_warnings(list(clause)::in,
    list(hlds_goal)::out, list(error_spec)::out) is det.

get_clause_disjuncts_and_warnings([], [], []).
get_clause_disjuncts_and_warnings([Clause | Clauses], Disjuncts, Warnings) :-
    Goal = Clause ^ clause_body,
    goal_to_disj_list(Goal, FirstDisjuncts),
    FirstWarnings = Clause ^ clause_statevar_warnings,
    get_clause_disjuncts_and_warnings(Clauses, LaterDisjuncts, LaterWarnings),
    Disjuncts = FirstDisjuncts ++ LaterDisjuncts,
    Warnings = FirstWarnings ++ LaterWarnings.

%-----------------------------------------------------------------------------%

introduce_exists_casts(PredIds, !ModuleInfo) :-
    module_info_get_preds(!.ModuleInfo, PredTable0),
    list.foldl(introduce_exists_casts_pred(!.ModuleInfo), PredIds,
        PredTable0, PredTable),
    module_info_set_preds(PredTable, !ModuleInfo).

:- pred introduce_exists_casts_pred(module_info::in, pred_id::in,
    pred_table::in, pred_table::out) is det.

introduce_exists_casts_pred(ModuleInfo, PredId, !PredTable) :-
    map.lookup(!.PredTable, PredId, PredInfo0),
    (
        % Optimise the common case.
        pred_info_get_existq_tvar_binding(PredInfo0, Subn),
        \+ map.is_empty(Subn),

        % Only process preds for which we copied clauses to procs.
        should_copy_clauses_to_procs(PredInfo0)
    ->
        pred_info_get_procedures(PredInfo0, Procs0),
        ProcIds = pred_info_all_non_imported_procids(PredInfo0),
        introduce_exists_casts_procs(ModuleInfo, PredInfo0, ProcIds,
            Procs0, Procs),
        pred_info_set_procedures(Procs, PredInfo0, PredInfo),
        map.det_update(PredId, PredInfo, !PredTable)
    ;
        true
    ).

:- pred introduce_exists_casts_procs(module_info::in, pred_info::in,
    list(proc_id)::in, proc_table::in, proc_table::out) is det.

introduce_exists_casts_procs(_, _, [], !Procs).
introduce_exists_casts_procs(ModuleInfo, PredInfo, [ProcId | ProcIds],
        !Procs) :-
    map.lookup(!.Procs, ProcId, ProcInfo0),
    introduce_exists_casts_proc(ModuleInfo, PredInfo, ProcInfo0, ProcInfo),
    map.det_update(ProcId, ProcInfo, !Procs),
    introduce_exists_casts_procs(ModuleInfo, PredInfo, ProcIds, !Procs).

introduce_exists_casts_proc(ModuleInfo, PredInfo, !ProcInfo) :-
    pred_info_get_arg_types(PredInfo, ArgTypes),
    pred_info_get_existq_tvar_binding(PredInfo, Subn),
    pred_info_get_class_context(PredInfo, PredConstraints),
    OrigArity = pred_info_orig_arity(PredInfo),
    NumExtraHeadVars = list.length(ArgTypes) - OrigArity,

    proc_info_get_varset(!.ProcInfo, VarSet0),
    proc_info_get_vartypes(!.ProcInfo, VarTypes0),
    proc_info_get_headvars(!.ProcInfo, HeadVars0),
    proc_info_get_goal(!.ProcInfo, Body0),
    proc_info_get_rtti_varmaps(!.ProcInfo, RttiVarMaps0),
    proc_info_get_argmodes(!.ProcInfo, ArgModes),

    (
        list.drop(NumExtraHeadVars, ArgTypes, OrigArgTypes0),
        list.split_list(NumExtraHeadVars, HeadVars0, ExtraHeadVars0,
            OrigHeadVars0),
        list.split_list(NumExtraHeadVars, ArgModes, ExtraArgModes0,
            OrigArgModes0)
    ->
        OrigArgTypes = OrigArgTypes0,
        ExtraHeadVars1 = ExtraHeadVars0,
        OrigHeadVars1 = OrigHeadVars0,
        ExtraArgModes = ExtraArgModes0,
        OrigArgModes = OrigArgModes0
    ;
        unexpected($module, $pred, "split_list failed")
    ),

    % Add exists_casts for any head vars which are existentially typed,
    % and for which the type is statically bound inside the procedure.
    % Subn represents which existential types are bound.
    introduce_exists_casts_for_head(ModuleInfo, Subn, OrigArgTypes,
        OrigArgModes, OrigHeadVars1, OrigHeadVars, VarSet0, VarSet1,
        VarTypes0, VarTypes1, [], ExistsCastHeadGoals),

    % Add exists_casts for any existential type_infos or typeclass_infos.
    % We determine which of these are existential by looking at the mode.
    %
    ExistConstraints = PredConstraints ^ exist_constraints,
    assoc_list.from_corresponding_lists(ExtraArgModes, ExtraHeadVars1,
        ExtraModesAndVars),
    introduce_exists_casts_extra(ModuleInfo, Subn, ExistConstraints,
        ExtraModesAndVars, ExtraHeadVars, VarSet1, VarSet, VarTypes1, VarTypes,
        RttiVarMaps0, RttiVarMaps, [], ExistsCastExtraGoals),

    Body0 = hlds_goal(_, GoalInfo0),
    goal_to_conj_list(Body0, Goals0),
    Goals = Goals0 ++ ExistsCastHeadGoals ++ ExistsCastExtraGoals,
    HeadVars = ExtraHeadVars ++ OrigHeadVars,
    NonLocals = set_of_var.list_to_set(HeadVars),
    goal_info_set_nonlocals(NonLocals, GoalInfo0, GoalInfo),
    Body = hlds_goal(conj(plain_conj, Goals), GoalInfo),
    proc_info_set_body(VarSet, VarTypes, HeadVars, Body, RttiVarMaps,
        !ProcInfo).

:- pred introduce_exists_casts_for_head(module_info::in, tsubst::in,
    list(mer_type)::in, list(mer_mode)::in, list(prog_var)::in,
    list(prog_var)::out, prog_varset::in, prog_varset::out,
    vartypes::in, vartypes::out, list(hlds_goal)::in, list(hlds_goal)::out)
    is det.

introduce_exists_casts_for_head(ModuleInfo, Subn, ArgTypes, ArgModes,
        !HeadVars, !VarSet, !VarTypes, !ExtraGoals) :-
    (
        ArgTypes = [],
        ArgModes = [],
        !.HeadVars = []
    ->
        true
    ;
        ArgTypes = [ArgType | ArgTypesRest],
        ArgModes = [ArgMode | ArgModesRest],
        !.HeadVars = [HeadVar0 | HeadVarsRest0]
    ->
        introduce_exists_casts_for_head(ModuleInfo, Subn, ArgTypesRest,
            ArgModesRest, HeadVarsRest0, HeadVarsRest, !VarSet, !VarTypes,
            !ExtraGoals),
        introduce_exists_casts_for_arg(ModuleInfo, Subn, ArgType, ArgMode,
            HeadVar0, HeadVar, !VarSet, !VarTypes, !ExtraGoals),
        !:HeadVars = [HeadVar | HeadVarsRest]
    ;
        unexpected($module, $pred, "length mismatch")
    ).

:- pred introduce_exists_casts_for_arg(module_info::in, tsubst::in,
    mer_type::in, mer_mode::in, prog_var::in, prog_var::out,
    prog_varset::in, prog_varset::out, vartypes::in, vartypes::out,
    list(hlds_goal)::in, list(hlds_goal)::out) is det.

introduce_exists_casts_for_arg(ModuleInfo, Subn, ExternalType, ArgMode,
        HeadVar0, HeadVar, !VarSet, !VarTypes, !ExtraGoals) :-
    apply_rec_subst_to_type(Subn, ExternalType, InternalType),
    (
        % Add an exists_cast for the head variable if its type
        % inside the procedure is different from its type at the
        % interface.
        InternalType \= ExternalType
    ->
        term.context_init(Context),
        update_var_type(HeadVar0, InternalType, !VarTypes),
        make_new_exist_cast_var(HeadVar0, HeadVar, !VarSet),
        add_var_type(HeadVar, ExternalType, !VarTypes),
        mode_get_insts(ModuleInfo, ArgMode, _, Inst),
        generate_cast_with_insts(exists_cast, HeadVar0, HeadVar, Inst, Inst,
            Context, ExtraGoal),
        !:ExtraGoals = [ExtraGoal | !.ExtraGoals]
    ;
        HeadVar = HeadVar0
    ).

:- pred introduce_exists_casts_extra(module_info::in, tsubst::in,
    list(prog_constraint)::in, assoc_list(mer_mode, prog_var)::in,
    list(prog_var)::out, prog_varset::in, prog_varset::out,
    vartypes::in, vartypes::out, rtti_varmaps::in,  rtti_varmaps::out,
    list(hlds_goal)::in, list(hlds_goal)::out) is det.

introduce_exists_casts_extra(_, _, ExistConstraints, [], [], !VarSet,
        !VarTypes, !RttiVarMaps, !ExtraGoals) :-
    (
        ExistConstraints = []
    ;
        ExistConstraints = [_ | _],
        unexpected($module, $pred, "length mismatch")
    ).

introduce_exists_casts_extra(ModuleInfo, Subn, ExistConstraints0,
        [ModeAndVar | ModesAndVars], [Var | Vars], !VarSet, !VarTypes,
        !RttiVarMaps, !ExtraGoals) :-
    ModeAndVar = ArgMode - Var0,
    ( mode_is_output(ModuleInfo, ArgMode) ->
        % Create the exists_cast goal.

        term.context_init(Context),
        make_new_exist_cast_var(Var0, Var, !VarSet),
        lookup_var_type(!.VarTypes, Var0, VarType),
        add_var_type(Var, VarType, !VarTypes),
        generate_cast(exists_cast, Var0, Var, Context, ExtraGoal),
        !:ExtraGoals = [ExtraGoal | !.ExtraGoals],

        % Update the rtti_varmaps. The old variable needs to have the
        % substitution applied to its type/constraint. The new variable
        % needs to be associated with the unsubstituted type/constraint.

        rtti_varmaps_var_info(!.RttiVarMaps, Var0, VarInfo),
        (
            VarInfo = type_info_var(TypeInfoType0),
            % For type_infos, the old variable needs to have the substitution
            % applied to its type, and the new variable needs to be associated
            % with the unsubstituted type.
            apply_rec_subst_to_type(Subn, TypeInfoType0, TypeInfoType),
            rtti_set_type_info_type(Var0, TypeInfoType, !RttiVarMaps),
            rtti_det_insert_type_info_type(Var, TypeInfoType0, !RttiVarMaps),
            ExistConstraints = ExistConstraints0
        ;
            VarInfo = typeclass_info_var(_),
            % For typeclass_infos, the constraint associated with the old
            % variable was derived from the constraint map, so all binding
            % and improvement has been applied. The new variable needs to
            % be associated with the corresponding existential head constraint,
            % so we pop one off the front of the list.
            (
                ExistConstraints0 = [ExistConstraint | ExistConstraints]
            ;
                ExistConstraints0 = [],
                unexpected($module, $pred, "missing constraint")
            ),
            rtti_det_insert_typeclass_info_var(ExistConstraint, Var,
                !RttiVarMaps),
            % We also need to ensure that all type variables in the constraint
            % have a location recorded, so we insert a location now if there
            % is not already one.
            ExistConstraint = constraint(_, ConstraintArgs),
            maybe_add_type_info_locns(ConstraintArgs, Var, 1, !RttiVarMaps)
        ;
            VarInfo = non_rtti_var,
            unexpected($module, $pred, "rtti_varmaps info not found")
        )
    ;
        Var = Var0,
        ExistConstraints = ExistConstraints0
    ),
    introduce_exists_casts_extra(ModuleInfo, Subn, ExistConstraints,
        ModesAndVars, Vars, !VarSet, !VarTypes, !RttiVarMaps, !ExtraGoals).

:- pred maybe_add_type_info_locns(list(mer_type)::in, prog_var::in, int::in,
    rtti_varmaps::in, rtti_varmaps::out) is det.

maybe_add_type_info_locns([], _, _, !RttiVarMaps).
maybe_add_type_info_locns([ArgType | ArgTypes], Var, Num, !RttiVarMaps) :-
    (
        ArgType = type_variable(TVar, _),
        \+ rtti_search_type_info_locn(!.RttiVarMaps, TVar, _)
    ->
        Locn = typeclass_info(Var, Num),
        rtti_det_insert_type_info_locn(TVar, Locn, !RttiVarMaps)
    ;
        true
    ),
    maybe_add_type_info_locns(ArgTypes, Var, Num + 1, !RttiVarMaps).

:- pred make_new_exist_cast_var(prog_var::in, prog_var::out,
    prog_varset::in, prog_varset::out) is det.

make_new_exist_cast_var(InternalVar, ExternalVar, !VarSet) :-
    varset.new_var(ExternalVar, !VarSet),
    varset.lookup_name(!.VarSet, InternalVar, InternalName),
    string.append("ExistQ", InternalName, ExternalName),
    varset.name_var(ExternalVar, ExternalName, !VarSet).

%-----------------------------------------------------------------------------%
:- end_module check_hlds.clause_to_proc.
%-----------------------------------------------------------------------------%
