%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et wm=4 tw=0
%-----------------------------------------------------------------------------%
% Copyright (C) 2009-2012 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: type_constraints.m
% Main author: aebert
%
% Constructs a set of constraints from a Mercury program,
% then solves these constraints in order to determine the
% types of all local variables in the program.
%
%-----------------------------------------------------------------------------%

:- module check_hlds.type_constraints.
:- interface.

:- import_module hlds.
:- import_module hlds.hlds_module.
:- import_module parse_tree.
:- import_module parse_tree.error_util.

:- import_module list.

:- pred typecheck_constraints(module_info::in, module_info::out,
    list(error_spec)::out) is det.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module hlds.goal_path.
:- import_module hlds.goal_util.
:- import_module hlds.hlds_clauses.
:- import_module hlds.hlds_data.
:- import_module hlds.hlds_goal.
:- import_module hlds.hlds_pred.
:- import_module hlds.pred_table.
:- import_module hlds.special_pred.
:- import_module mdbcomp.
:- import_module mdbcomp.goal_path.
:- import_module mdbcomp.prim_data.
:- import_module mdbcomp.sym_name.
:- import_module parse_tree.builtin_lib_types.
:- import_module parse_tree.mercury_to_mercury.
:- import_module parse_tree.prog_data.
:- import_module parse_tree.prog_event.
:- import_module parse_tree.prog_type.
:- import_module parse_tree.prog_type_subst.

:- import_module assoc_list.
:- import_module bimap.
:- import_module bool.
:- import_module counter.
:- import_module int.
:- import_module io.
:- import_module map.
:- import_module maybe.
:- import_module pair.
:- import_module require.
:- import_module set.
:- import_module string.
:- import_module term.
:- import_module term_io.
:- import_module varset.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- type type_constraint
    --->    tconstr_conj(
                % A conjunction of constraints, all of which must hold.
                conj_type_constraint
            )
    ;       tconstr_disj(
                % A disjunction of conjunctions of constraints, caused
                % by ambiguity in unifications or calls.
                list(conj_type_constraint),

                % "Yes" if the disjunction has been reduced to a single
                % possible conjunction by constraint propagation.
                maybe(conj_type_constraint)
            ).

:- type conj_type_constraint
    --->    ctconstr(
                % The simple constraints which make up the conjunction.
                tconstr_simples     :: list(simple_type_constraint),

                % Whether the constraint is still active, or has been
                % found to be unsatisfiable.
                tconstr_activity    :: tconstr_activity,

                % The context of the goal that creates the conjunction.
                tconstr_context     :: prog_context,

                % The id of the goal which created the constraint,
                % if it is relevant.
                tconstr_goal_id     :: maybe(goal_id),

                % The predicate id of the predicate call, if this is a
                % predicate call constraint.
                tconstr_pred_id     :: maybe(pred_id)
            ).

:- type tconstr_activity
    --->    tconstr_active
            % The constraint is still relevant.

    ;       tconstr_unsatisfiable.
            % The constraint is only relevant for error diagnosis.

:- type simple_type_constraint
    --->    stconstr(
                tvar,       % The variable whose type is being constrained.
                mer_type    % The type to which the variable is being assigned.
            ).

:- type type_constraint_set == set(type_constraint_id).

:- type type_constraint_map == map(type_constraint_id, type_constraint).

    % A map from program variables to all constraints involving those
    % variables.
    %
:- type var_constraint_map == map(tvar, list(type_constraint_id)).

    % A map from program variables to the type variables they correspond to.
    % The one-to-one correspondence is usegful during the main phase of type
    % constraint solving.
    %
:- type prog_var_map == bimap(prog_var, tvar).

    % simple_prog_var_map is used after regular constraint solving, when
    % multiple program variables can correspond to the same type variable.
    %
:- type simple_prog_var_map == map(prog_var, tvar).

    % A map from type variables to their possible types.
    %
:- type type_domain_map == map(tvar, type_domain).

:- type type_domain
    --->    tdomain(set(mer_type))
            % A type-domain consisting of multiple possible types.

    ;       tdomain_singleton(mer_type)
            % A domain that has been fixed to one definite type. This
            % is used to avoid propagating on the same variable twice.

    ;       tdomain_any.
            % This represents an unbound type.

:- type type_constraint_info
    --->    tconstr_info(
                % A map from program variables to their corresponding
                % type variables.
                tconstr_var_map             :: prog_var_map,

                % A counter for constraint ids.
                tconstr_constraint_counter  :: type_constraint_counter,

                % A map from constraint ids to constraints.
                tconstr_constraint_map      :: type_constraint_map,

                % A map from type variables to the constraints
                % which involve them.
                tconstr_var_constraints     :: var_constraint_map,

                % The set of type variables used in the constraints.
                tconstr_tvarset             :: tvarset,

                % All errors encountered during typechecking.
                tconstr_error_specs         :: error_specs
            ).

:- type type_constraint_solution
    --->    tconstr_solution(
                tconstr_sol_domain_maps     :: list(type_domain_map),
                tconstr_sol_constraint_map  :: type_constraint_map,
                tconstr_sol_success         :: bool
            ).

    % Maps from ids of program elements to their definitions,
    % extracted from the HLDS.
    %
:- type tconstr_environment
    --->    tconstr_environment(
                event_env   :: event_env,
                class_env   :: class_env,
                func_env    :: func_env,
                pred_env    :: pred_env
                % type_env  :: type_env,
            ).

:- type event_env == event_spec_map.
:- type class_env == class_table.
% :- type type_env == type_table.
:- type func_env == cons_table.
:- type pred_env == predicate_table.

:- type type_constraint_id == int.
:- type type_constraint_counter == counter.

:- type error_specs == list(error_spec).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

    % This is the predicate called by the compiler to perform the typecheck
    % pass.
    %
typecheck_constraints(!HLDS, Specs) :-
    % hlds_module.module_info_get_type_table(!.HLDS, TypeEnv),
    hlds_module.module_info_get_event_set(!.HLDS, event_set(_, EventEnv)),
    hlds_module.module_info_get_class_table(!.HLDS, ClassEnv),
    hlds_module.module_info_get_cons_table(!.HLDS, FuncEnv),
    hlds_module.module_info_get_predicate_table(!.HLDS, PredEnv),
    Environment0 = tconstr_environment(EventEnv, ClassEnv, FuncEnv, PredEnv),

    module_info_get_valid_predids(PredIds, !HLDS),
    list.foldl3(typecheck_one_predicate_if_needed, PredIds,
        Environment0, _, !HLDS, [], Specs).

:- pred typecheck_one_predicate_if_needed(pred_id::in, tconstr_environment::in,
    tconstr_environment::out, module_info::in, module_info::out,
    error_specs::in, error_specs::out) is det.

typecheck_one_predicate_if_needed(PredId, !Environment, !HLDS, !Specs) :-
    predicate_table_get_preds(!.Environment ^ pred_env, Preds0),
    map.lookup(Preds0, PredId, PredInfo),
    (
        % Compiler-generated predicates are created already type-correct,
        % so there's no need to typecheck them. The same is true for builtins.
        % However, compiler-generated unify predicates are not guaranteed to be
        % type-correct if they call a user-defined equality or comparison
        % predicate or if it is a special pred for an existentially quantified
        % type.
        (
            is_unify_or_compare_pred(PredInfo),
            \+ special_pred_needs_typecheck(PredInfo, !.HLDS)
        ;
            pred_info_is_builtin(PredInfo)
        )
    ->
        pred_info_get_clauses_info(PredInfo, ClausesInfo0),
        clauses_info_get_clauses_rep(ClausesInfo0, ClausesRep0, _ItemNumbers),
        IsEmpty = clause_list_is_empty(ClausesRep0),
        (
            IsEmpty = yes,
            pred_info_mark_as_external(PredInfo, PredInfo1),
            map.det_update(PredId, PredInfo1, Preds0, Preds),
            PredEnv0 = !.Environment ^ pred_env,
            predicate_table_set_preds(Preds, PredEnv0, PredEnv),
            module_info_set_predicate_table(PredEnv, !HLDS),
            !Environment ^ pred_env := PredEnv
        ;
            IsEmpty = no
        )
    ;
        typecheck_one_predicate(PredId, !Environment, !HLDS, !Specs)
    ).

:- pred typecheck_one_predicate(pred_id::in,
    tconstr_environment::in, tconstr_environment::out,
    module_info::in, module_info::out,
    error_specs::in, error_specs::out) is det.

typecheck_one_predicate(PredId, !Environment, !HLDS, !Specs) :-
    some [!Preds, !PredInfo, !ClausesInfo, !Clauses, !Goals, !PredEnv,
        !TCInfo, !Vartypes]
    (
        % Find the clause list in the predicate definition.
        !:PredEnv = !.Environment ^ pred_env,
        predicate_table_get_preds(!.PredEnv, !:Preds),
        map.lookup(!.Preds, PredId, !:PredInfo),
        pred_info_get_typevarset(!.PredInfo, TVarSet),
        pred_info_get_context(!.PredInfo, Context),
        pred_info_get_clauses_info(!.PredInfo, !:ClausesInfo),
        clauses_info_get_varset(!.ClausesInfo, ProgVarSet),

        trace [compile_time(flag("type_error_diagnosis")), io(!IO)] (
            LineNumber = string.int_to_string(term.context_line(Context)),
            FileName = term.context_file(Context),
            PredNumber = int_to_string(pred_id_to_int(PredId)),
            io.write_string("=== Predicate " ++ PredNumber ++ " [" ++
                FileName ++ ": " ++ LineNumber ++ "] ===\n", !IO)
        ),

        % Create a set of constraints on the types of the head variables.
        clauses_info_get_headvar_list(!.ClausesInfo, HeadVars),
        pred_info_get_arg_types(!.PredInfo, HeadTypes),
        prog_type.type_vars_list(HeadTypes, HeadTVars),
        ( list.same_length(HeadTypes, HeadVars) ->
            list.foldl_corresponding(variable_assignment_constraint(Context),
                HeadVars, HeadTypes, tconstr_info(bimap.init, counter.init(0),
                map.init, map.init, TVarSet, []), !:TCInfo)
        ;
            unexpected($module, $pred, "head variable types vs vars mismatch")
        ),

        % Generate constraints for each clause of the predicate.
        fill_goal_id_slots_in_clauses(!.HLDS, ContainingGoalMap,
            !ClausesInfo),
        ForwardGoalPathMap =
            create_forward_goal_path_map(ContainingGoalMap),
        clauses_info_get_clauses_rep(!.ClausesInfo, ClausesRep0, ItemNumbers),
        get_clause_list(ClausesRep0, !:Clauses),
        list.map(get_clause_body, !.Clauses, !:Goals),
        list.foldl(goal_to_constraint(!.Environment), !.Goals, !TCInfo),
        trace [compile_time(flag("type_error_diagnosis")), io(!IO)] (
            print_pred_constraint(!.TCInfo, ProgVarSet, !IO)
        ),

        % Solve all the constraints.
        find_type_constraint_solutions(Context, ProgVarSet, DomainMap0,
            !TCInfo),
        list.foldl2_corresponding(unify_equal_tvars(!.TCInfo, set.init),
            HeadTVars, HeadTVars,
            map.init, ReplacementMap, DomainMap0, DomainMap),
        trace [compile_time(flag("type_error_diagnosis")), io(!IO)] (
            print_constraint_solution(!.TCInfo, ProgVarSet, DomainMap, !IO)
        ),

        % Update the HLDS with the results of the solving and report any
        % ambiguity errors found in this process.
        list.map2(
            update_goal(!.PredEnv, !.TCInfo ^ tconstr_constraint_map,
                ForwardGoalPathMap),
            !Goals, PredErrors),
        create_vartypes_map(Context, ProgVarSet, !.TCInfo ^ tconstr_tvarset,
            !.TCInfo ^ tconstr_var_map, DomainMap, ReplacementMap, !:Vartypes,
            VarTypeErrors),
        list.map_corresponding(set_clause_body, !.Goals, !Clauses),
        list.condense([VarTypeErrors | PredErrors], NewErrors),
        list.foldl(add_message_to_spec, NewErrors, !TCInfo),
        set_clause_list(!.Clauses, ClausesRep),
        clauses_info_set_clauses_rep(ClausesRep, ItemNumbers, !ClausesInfo),
        list.foldl(add_unused_prog_var(!.TCInfo), HeadVars, !Vartypes),
        clauses_info_set_vartypes(!.Vartypes, !ClausesInfo),
        pred_info_set_clauses_info(!.ClausesInfo, !PredInfo),
        pred_info_set_typevarset(!.TCInfo ^ tconstr_tvarset, !PredInfo),
        map.det_update(PredId, !.PredInfo, !Preds),
        predicate_table_set_preds(!.Preds, !PredEnv),
        module_info_set_predicate_table(!.PredEnv, !HLDS),
        !Environment ^ pred_env := !.PredEnv,
        !:Specs = !.TCInfo ^ tconstr_error_specs ++ !.Specs
    ).

%-----------------------------------------------------------------------------%
%
% General typechecking utility predicates.
%

    % A compiler-generated predicate only needs type checking if
    % (a) it is a user-defined equality pred, or
    % (b) it is the unification or comparison predicate for an existially
    %     quantified type.
    %
    % In case (b), we need to typecheck it to fill in the head_type_params
    % field in the pred_info.
    %
:- pred special_pred_needs_typecheck(pred_info::in, module_info::in)
    is semidet.

special_pred_needs_typecheck(PredInfo, ModuleInfo) :-
    % Check if the predicate is a compiler-generated special predicate,
    % and if so, for which type.
    pred_info_get_origin(PredInfo, Origin),
    Origin = origin_special_pred(SpecialPredId - TypeCtor),

    % Check that the special pred isn't one of the builtin types which don't
    % have a hlds_type_defn.
    \+ list.member(TypeCtor, builtin_type_ctors_with_no_hlds_type_defn),

    % Check whether that type is a type for which there is a user-defined
    % equality predicate or which is existentially typed.
    module_info_get_type_table(ModuleInfo, TypeTable),
    lookup_type_ctor_defn(TypeTable, TypeCtor, TypeDefn),
    hlds_data.get_type_defn_body(TypeDefn, Body),
    special_pred_for_type_needs_typecheck(ModuleInfo, SpecialPredId, Body).

    % Updates the goal with the pred_ids of all predicates called in the goal.
    % If there is an ambiguous predicate call, chooses one predicate to be
    % the "correct" one and returns an error message describing the problem.
    %
:- pred update_goal(pred_env::in, type_constraint_map::in,
    goal_forward_path_map::in, hlds_goal::in, hlds_goal::out,
    list(error_msg)::out) is det.

update_goal(PredEnv, ConstraintMap, ForwardGoalPathMap, !Goal, Errors) :-
    Disjunctions = map.values(ConstraintMap),
    list.filter_map(has_one_disjunct, Disjunctions, Conjunctions),
    list.filter_map(pred_constraint_info, Conjunctions, DefinitePredData),
    list.filter_map(has_multiple_disjuncts, Disjunctions, AmbigDisjuncts),
    list.filter_map(diagnose_ambig_pred_error(PredEnv), AmbigDisjuncts,
        Errors),

    list.map(list.filter_map(pred_constraint_info), AmbigDisjuncts,
        AmbigPredDatas),
    AmbigPredData = list.filter_map(list.head, AmbigPredDatas),
    PredData = DefinitePredData ++ AmbigPredData,
    list.foldl(apply_pred_data_to_goal(ForwardGoalPathMap), PredData, !Goal).

:- pred apply_pred_data_to_goal(goal_forward_path_map::in,
    pair(goal_id, pred_id)::in, hlds_goal::in, hlds_goal::out) is det.

apply_pred_data_to_goal(ForwardGoalPathMap, GoalId - PredId, !Goal) :-
    map.lookup(ForwardGoalPathMap, GoalId, GoalPath),
    maybe_transform_goal_at_goal_path(set_goal_pred_id(PredId), GoalPath,
        !.Goal, Result),
    (
        Result = ok(!:Goal)
    ;
        ( Result = error(_)
        ; Result = goal_not_found
        ),
        unexpected($module, $pred, "not ok")
    ).

:- pred set_goal_pred_id(pred_id::in, hlds_goal::in,
    maybe_error(hlds_goal)::out) is det.

set_goal_pred_id(PredId, Goal0, MaybeGoal) :-
    Goal0 = hlds_goal(GoalExpr0, GoalInfo),
    ( GoalExpr0 = plain_call(_, _, _, _, _, _) ->
        trace [compile_time(flag("type_error_diagnosis")), io(!IO)] (
            Context = goal_info_get_context(GoalInfo),
            LineNumber = term.context_line(Context),
            FileName = term.context_file(Context),
            PredName = sym_name_to_string(GoalExpr0 ^ call_sym_name),
            io.format("  Predicate %s PredName (%s:%d) has id %d\n",
                [s(PredName), s(FileName), i(LineNumber),
                    i(pred_id_to_int(PredId))],
                !IO)
        ),
        GoalExpr = GoalExpr0 ^ call_pred_id := PredId,
        Goal = hlds_goal(GoalExpr, GoalInfo),
        MaybeGoal = ok(Goal)
    ;
        MaybeGoal = error("Goal was not a plain call")
    ).

    % The following predicates extract the disjuncts from type constraints.
    %
:- pred has_one_disjunct(type_constraint::in, conj_type_constraint::out)
    is semidet.

has_one_disjunct(tconstr_disj(Cs, no), C) :-
    list.filter(still_active, Cs, [C]).
has_one_disjunct(tconstr_disj(_, yes(C)), C).
has_one_disjunct(tconstr_conj(C), C).

:- pred get_first_disjunct(type_constraint::in, conj_type_constraint::out)
    is semidet.

get_first_disjunct(tconstr_disj(Cs, no), C) :-
    list.filter(still_active, Cs, [C | _]).
get_first_disjunct(tconstr_disj(_, yes(C)), C).
get_first_disjunct(tconstr_conj(C), C).

:- pred has_multiple_disjuncts(type_constraint::in,
    list(conj_type_constraint)::out)  is semidet.

has_multiple_disjuncts(tconstr_disj(Cs0, _), Cs) :-
    list.filter(still_active, Cs0, Cs),
    Cs = [_, _ | _].

    % Creates the vartypes map, which is inserted into the relevant pred_info
    % and used by the rest of the compiler.
    %
:- pred create_vartypes_map(prog_context::in, prog_varset::in, tvarset::in,
    prog_var_map::in, type_domain_map::in, simple_prog_var_map::in,
    vartypes::out, list(error_msg)::out) is det.

create_vartypes_map(Context, ProgVarSet, TVarSet, VarMap, DomainMap,
        ReplacementMap, Vartypes, Errors) :-
    bimap.ordinates(VarMap, ProgVars),
    list.map2(find_variable_type(Context, ProgVarSet, TVarSet, VarMap,
        DomainMap, ReplacementMap), ProgVars, Types, MaybeErrors),
    list.filter_map(maybe_is_yes, MaybeErrors, Errors),
    vartypes_from_corresponding_lists(ProgVars, Types, Vartypes).

    % If a variable has a domain consisting of one type, gives it that type.
    % Otherwise, assign it to a type consisting of the type variable assigned
    % to it by constraint generation, after the type variable replacement
    % performed by unify_equal_tvars.
    %
:- pred find_variable_type(prog_context::in, prog_varset::in, tvarset::in,
    prog_var_map::in, type_domain_map::in, simple_prog_var_map::in,
    prog_var::in, mer_type::out, maybe(error_msg)::out) is det.

find_variable_type(Context, ProgVarSet, TVarSet, VarMap, DomainMap,
        ReplacementMap, Var, Type, Error) :-
    bimap.lookup(VarMap, Var, TVar),
    ( map.search(ReplacementMap, Var, ReplacementType) ->
        DefaultType = tvar_to_type(ReplacementType)
    ;
        DefaultType = tvar_to_type(TVar)
    ),
    ( map.search(DomainMap, TVar, Domain) ->
        (
            Domain = tdomain_any,
            Type = DefaultType,
            Error = no
        ;
            Domain = tdomain_singleton(Type),
            Error = no
        ;
            Domain = tdomain(Types),
            ( set.is_singleton(Types, Type0) ->
                Type = Type0,
                Error = no
            ; set.empty(Types) ->
                Type = DefaultType,
                Error = no  % This error is handled elsewhere.
            ;
                Type = DefaultType,
                VarName = mercury_var_to_string(ProgVarSet, no, Var),
                list.map(type_to_string(TVarSet), set.to_sorted_list(Types),
                    TypeStrings),
                TypesString = string.join_list(" or ", TypeStrings),
                Error = yes(simple_msg(Context, [always([words("Error:"),
                    words("ambiguous overloading causes type ambiguity."),
                    nl, words("Possible type assignments include:"), nl,
                    fixed(VarName), suffix(": "), words(TypesString)])]))
            )
        )
    ;
        Type = DefaultType,
        Error = no
    ).

:- pred get_clause_body(clause::in, hlds_goal::out) is det.

get_clause_body(Clause, Clause ^ clause_body).

:- pred set_clause_body(hlds_goal::in, clause::in, clause::out) is det.

set_clause_body(Goal, Clause, Clause ^ clause_body := Goal).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
%
% Constraint solving.
%

    % Tries to solve a constraint on the types of variables in a predicate.
    % If a definite solution cannot be found, use labeling to guess the value
    % of the variable with the smallest domain, then propagate this to
    % all constraints. If exactly one guess provides a correct solution,
    % return that solution. Otherwise, generate an error message explaining
    % the problem.
    %
:- pred find_type_constraint_solutions(prog_context::in, prog_varset::in,
    type_domain_map::out,
    type_constraint_info::in, type_constraint_info::out) is det.

find_type_constraint_solutions(Context, ProgVarSet, DomainMap, !TCInfo) :-
    !.TCInfo = tconstr_info(_, _, ConstraintMap0, VarConstraints, TVarSet, _),
    solve_constraint_labeling(TVarSet, VarConstraints, ConstraintMap0,
        map.init, map.init, LabeledSolution),
    LabeledSolution = tconstr_solution(Solutions, ConstraintMap, Success),
    (
        Solutions = [],
        % This shouldn't happen.
        % XXX zs: The reason *why* it should not happen should be documented.
        unexpected($module, $pred,
            "cannot find any possible solutions for the type constraints")
    ;
        Solutions = [FirstSolution | LaterSolutions],
        (
            Success = no,
            % Unsatisfiability error (no solutions). If labeling was required
            % and no labeling assignment produced a solution, pick an arbitrary
            % labeling to report (this should be rare in real programs).
            trace [compile_time(flag("type_error_reporting")), io(!IO)] (
                io.write_string("\nUnsatisfiability error\n", !IO)
            ),
            map.to_assoc_list(FirstSolution, SolutionAssocList),
            list.filter_map(has_empty_domain, SolutionAssocList, ErrorTVars),
            list.map(diagnose_unsatisfiability_error(!.TCInfo, Context,
                ProgVarSet), ErrorTVars, ErrorMessages),
            list.foldl(add_message_to_spec, ErrorMessages, !TCInfo),
            list.foldl(map.union(type_domain_union), Solutions,
                map.init, DomainMap)
        ;
            Success = yes,
            (
                LaterSolutions = [],
                % Type correct (one solution).
                DomainMap = FirstSolution
            ;
                LaterSolutions = [_ | _],
                % Ambiguity error (many solutions).
                list.foldl(map.union(type_domain_union), Solutions, map.init,
                    DomainMap),
                trace [compile_time(flag("type_error_reporting")), io(!IO)] (
                    io.write_string("\nAmbiguity error\n", !IO)
                )
            )
        )
    ),
    !TCInfo ^ tconstr_constraint_map := ConstraintMap.

:- pred solve_constraint_labeling(tvarset::in, var_constraint_map::in,
    type_constraint_map::in, type_domain_map::in, type_domain_map::in,
    type_constraint_solution::out) is det.

solve_constraint_labeling(TVarSet, VarConstraints, ConstraintMap0, DomainMap0,
        Guesses, Solution) :-
    trace [compile_time(flag("type_constraint_prop")), io(!IO)] (
        map.to_assoc_list(Guesses, GuessesAssocList),
        list.foldl(print_guess(TVarSet), GuessesAssocList, !IO)
    ),
    map.union(type_domain_intersect, Guesses, DomainMap0, GuessMap),
    solve_constraint(TVarSet, VarConstraints, ConstraintMap0, ConstraintMap1,
        GuessMap, DomainMap1),
    ( constraint_has_no_solutions(DomainMap1) ->
        DomainMaps = [DomainMap1],
        ConstraintMap = ConstraintMap1,
        Success = no
    ; constraint_has_multiple_solutions(DomainMap1, Var, Domains) ->
        % If there are multiple solutions, pick the variable with the smallest
        % domain. Try to solve the constraints for each valuation of the
        % variable, then return any valuations which succeed. If none succeed,
        % return all valuations and report a failure.
        NewGuesses = list.map(map.set(Guesses, Var), Domains),
        list.map(solve_constraint_labeling(TVarSet, VarConstraints,
            ConstraintMap1, DomainMap1), NewGuesses, Solutions),
        list.filter(solution_is_invalid, Solutions,
            FailSolutions, SuccessSolutions),
        (
            SuccessSolutions = [],
            list.map(type_constraint_solution_get_domains,
                FailSolutions, DomainMaps0),
            list.condense(DomainMaps0, DomainMaps),
            list.map(type_constraint_solution_get_constraint_map,
                FailSolutions, RelevantConstraintMaps),
            Success = no
        ;
            SuccessSolutions = [_ | _],
            list.map(type_constraint_solution_get_domains,
                SuccessSolutions, DomainMaps0),
            list.condense(DomainMaps0, DomainMaps),
            list.map(type_constraint_solution_get_constraint_map,
                SuccessSolutions, RelevantConstraintMaps),
            Success = yes
        ),
        (
            RelevantConstraintMaps = [],
            ConstraintMap = map.init
        ;
            RelevantConstraintMaps = [RelevantHead | RelevantTail],
            list.foldl(map.union(merge_type_constraints), RelevantTail,
                RelevantHead, ConstraintMap)
        )
    ;
        DomainMaps = [DomainMap1],
        ConstraintMap = ConstraintMap1,
        Success = yes
    ),
    Solution = tconstr_solution(DomainMaps, ConstraintMap, Success).

:- pred solution_is_invalid(type_constraint_solution::in) is semidet.

solution_is_invalid(tconstr_solution(_, _, no)).

:- pred type_constraint_solution_get_domains(type_constraint_solution::in,
    list(type_domain_map)::out) is det.

type_constraint_solution_get_domains(T, T ^ tconstr_sol_domain_maps).

:- pred type_constraint_solution_get_constraint_map(
    type_constraint_solution::in, type_constraint_map::out) is det.

type_constraint_solution_get_constraint_map(T, T ^ tconstr_sol_constraint_map).

    % Restricts the domain of each variable in the constraint based on all
    % information in the constraint. If the domain map is unchanged in one pass
    % (i.e., a fixed point), or the constraint is found to be unsatisfiable,
    % the domain map is returned. Otherwise, solve_constraint is called
    % again with the new domain information.
    %
:- pred solve_constraint(tvarset::in, var_constraint_map::in,
    type_constraint_map::in, type_constraint_map::out,
    type_domain_map::in, type_domain_map::out) is det.

solve_constraint(TVarSet, VarConstraints, !ConstraintMap, !DomainMap) :-
    ConstraintMap0 = !.ConstraintMap,
    DomainMap0 = !.DomainMap,
    ConstraintIds = map.keys(!.ConstraintMap),
    list.foldl2(propagate(TVarSet, VarConstraints), ConstraintIds,
        !ConstraintMap, !DomainMap),
    (
        % Failure.
        constraint_has_no_solutions(!.DomainMap)
    ->
        true
    ;
        % Fixed-point reached (success).
        !.ConstraintMap = ConstraintMap0,
        !.DomainMap = DomainMap0
    ->
        true
    ;
        % Need to iterate again.
        solve_constraint(TVarSet, VarConstraints, !ConstraintMap, !DomainMap)
    ).

    % Given the information from a single constraint, updates the domains of
    % each variable in the constraint. If any variable is reduced to a
    % singleton domain, propagates this information to all other constraints
    % involving that variable.
    %
:- pred propagate(tvarset::in, var_constraint_map::in, type_constraint_id::in,
    type_constraint_map::in, type_constraint_map::out,
    type_domain_map::in, type_domain_map::out) is det.

propagate(TVarSet, VarConstraints, ConstraintId, !ConstraintMap, !DomainMap) :-
    % Update the domain of each variable in the constraint.
    map.lookup(!.ConstraintMap, ConstraintId, Constraint0),
    find_domain(Constraint0, Constraint, !.DomainMap, NewDomainMap),
    % Print the changes to the domain map.
    trace [compile_time(flag("type_constraint_prop")), io(!IO)] (
        io.format("Constraint %d:\n", [i(ConstraintId)], !IO),
        map.to_sorted_assoc_list(NewDomainMap, NewDomainAssocList),
        list.foldl(print_domain_map_change(TVarSet, !.DomainMap),
            NewDomainAssocList, !IO),
        print_constraint_change(TVarSet, Constraint0, Constraint, !IO)
    ),
    !:DomainMap = NewDomainMap,
    map.det_update(ConstraintId, Constraint, !ConstraintMap),
    % If any variable domains have been reduced to singleton domains
    % by this constraint, update the status of those variables and
    % propagate to other constriants involving them.
    tvars_in_constraint(Constraint, TVars),
    list.filter(has_singleton_domain(!.DomainMap), TVars, SingletonVars),
    list.foldl(update_singleton_domain, SingletonVars, !DomainMap),
    list.filter_map(map.search(VarConstraints),
        SingletonVars, PropConstraints0),
    PropConstraints = list.remove_dups(list.condense(PropConstraints0)),
    list.foldl2(propagate(TVarSet, VarConstraints), PropConstraints,
        !ConstraintMap, !DomainMap).

    % Given a variable and a list of constraints on that variable, enumerates
    % the possible types of that variable. Also, marks as unsatisfiable any
    % constraints that are unsatisfiable, given the current variable domains.
    %
:- pred create_domain(type_domain_map::in, conj_type_constraint::in,
    conj_type_constraint::out, type_domain_map::out) is det.

create_domain(!.DomainMap, !Constraint, !:DomainMap) :-
    conj_find_domain(!Constraint, !DomainMap).

    % Finds the domain of a type variable, given its existing domain and a
    % set of constraints on its type. Will mark as unsatisfiable any
    % constraints that are unsatisfiable.
    %
:- pred find_domain(type_constraint::in, type_constraint::out,
    type_domain_map::in, type_domain_map::out) is det.

    % A conjunction of constraints requires each constraint to be met.
    %
find_domain(Constraint0, Constraint, !DomainMap) :-
    (
        Constraint0 = tconstr_conj(ConjConstraints0),
        conj_find_domain(ConjConstraints0, ConjConstraints, !DomainMap),
        Constraint = tconstr_conj(ConjConstraints)
    ;
        Constraint0 = tconstr_disj(DisjConstraints0, yes(SingleConstraints0)),
        conj_find_domain(SingleConstraints0, SingleConstraints, !DomainMap),
        Constraint = tconstr_disj(DisjConstraints0, yes(SingleConstraints))
    ;
        Constraint0 = tconstr_disj(DisjConstraints0, no),
        % A disjunction of constraints means the domain is restricted to
        % the union of all type assignments in the each active disjunct.
        some [!DisjConstraints] (
            !:DisjConstraints = DisjConstraints0,

            % Generates a distinct domain map for each disjunct, unifies each
            % domain in the domain map to get an overall domain for the
            % disjunct, then takes the intersection of this with the existing
            % domain map.
            list.filter(still_active, !.DisjConstraints,
                !:DisjConstraints, InactiveConstraints),
            list.map2(create_domain(!.DomainMap), !.DisjConstraints,
                !:DisjConstraints, Domains),
            (
                Domains = [],
                DisjDomain = map.init
            ;
                Domains = [HeadDomain | TailDomains],
                list.foldl(map.intersect(type_domain_union), TailDomains,
                    HeadDomain, DisjDomain)
            ),
            map.union(type_domain_intersect, DisjDomain, !DomainMap),
            % If there is only one active disjunct remaining, then mark
            % the disjunction as such, which effectively turns the constraint
            % into a conjunction constraint.
            list.filter(still_active, !.DisjConstraints, Active),
            ( Active = [SingleConstraint0] ->
                SingleConstraint = yes(SingleConstraint0)
            ;
                SingleConstraint = no
            ),
            list.append(InactiveConstraints, !DisjConstraints),
            DisjConstraints = !.DisjConstraints
        ),
        Constraint = tconstr_disj(DisjConstraints, SingleConstraint)
    ).

    % Finds the domain of a conjunction of constraints. If the conjunction is
    % unsatisfiable, marks it as unsatisfiable. If the domain of any type
    % variable in the conjunct is reduced, propagate this information back to
    % conj_find_domain.
    %
:- pred conj_find_domain(conj_type_constraint::in, conj_type_constraint::out,
    type_domain_map::in, type_domain_map::out) is det.

conj_find_domain(!ConjTypeConstraint, DomainMap0, DomainMap) :-
    (
        !.ConjTypeConstraint = ctconstr(_, tconstr_unsatisfiable, _, _, _),
        DomainMap = DomainMap0
    ;
        !.ConjTypeConstraint = ctconstr(Constraints, tconstr_active, Context,
            GoalId, PredId),
        list.foldl(simple_find_domain, Constraints, DomainMap0, DomainMap1),
        ( constraint_is_satisfiable(DomainMap1, Constraints) ->
            map.to_assoc_list(DomainMap1, AssocDomain1),
            ( list.all_true(domain_map_unchanged(DomainMap0), AssocDomain1) ->
                DomainMap = DomainMap1
            ;
                conj_find_domain(!ConjTypeConstraint, DomainMap1, DomainMap)
            )
        ;
            !:ConjTypeConstraint = ctconstr(Constraints, tconstr_unsatisfiable,
                Context, GoalId, PredId),
            DomainMap = DomainMap1
        )
    ).

    % Finds the domain of a type variable based on the information provided by
    % a simple type constraint, and the existing domain of the variable.
    %
:- pred simple_find_domain(simple_type_constraint::in,
    type_domain_map::in, type_domain_map::out) is det.

simple_find_domain(stconstr(TVarA, TypeA), !DomainMap) :-
    % If the type is a compound type (e.g., maybe(T)), we try to further
    % restrict its type based on what (if anything) we know about
    % the types of its arguments.

    (
        % If two type variables are unified, the domain of each is restricted
        % to the insersection of the domains.
        TypeA = type_variable(TVarB, _),
        ( map.search(!.DomainMap, TVarB, DomainBPrime) ->
            DomainB = DomainBPrime
        ;
            DomainB = tdomain_any,
            map.det_insert(TVarB, DomainB, !DomainMap)
        ),
        ( map.search(!.DomainMap, TVarA, DomainA) ->
            type_domain_intersect(DomainA, DomainB, NewDomain),
            map.det_update(TVarA, NewDomain, !DomainMap),
            map.det_update(TVarB, NewDomain, !DomainMap)
        ;
            map.det_insert(TVarA, DomainB, !DomainMap)
        )
    ;
        TypeA = defined_type(Name, ArgTypes0, Kind),
        list.map(find_type_of_tvar(!.DomainMap), ArgTypes0, ArgTypes),
        NewTypeA = defined_type(Name, ArgTypes, Kind),
        restrict_domain(TVarA, NewTypeA, !DomainMap)
    ;
        TypeA = builtin_type(_),
        restrict_domain(TVarA, TypeA, !DomainMap)
    ;
        TypeA = tuple_type(ArgTypes0, Kind),
        list.map(find_type_of_tvar(!.DomainMap), ArgTypes0, ArgTypes),
        NewTypeA = tuple_type(ArgTypes, Kind),
        restrict_domain(TVarA, NewTypeA, !DomainMap)
    ;
        TypeA = higher_order_type(ArgTypes0, ReturnType0, Purity, Lambda),
        list.map(find_type_of_tvar(!.DomainMap), ArgTypes0, ArgTypes),
        map_maybe(find_type_of_tvar(!.DomainMap), ReturnType0, ReturnType),
        NewTypeA = higher_order_type(ArgTypes, ReturnType, Purity, Lambda),
        restrict_domain(TVarA, NewTypeA, !DomainMap)
    ;
        TypeA = apply_n_type(Return, ArgTypes0, Kind),
        list.map(find_type_of_tvar(!.DomainMap), ArgTypes0, ArgTypes),
        NewTypeA = apply_n_type(Return, ArgTypes, Kind),
        restrict_domain(TVarA, NewTypeA, !DomainMap)
    ;
        TypeA = kinded_type(KindedTypeA, _),
        simple_find_domain(stconstr(TVarA, KindedTypeA), !DomainMap)
    ).

    % Finds each variable which is unified to the target variable. Replaces
    % these variables with the replacement variable in the prog_var<->tvar
    % map. Recursively calls on each of these variables. In this way, replaces
    % assignments of program variables to equivalent type variables with
    % assignments of program variables to the same type variable.
    %
:- pred unify_equal_tvars(type_constraint_info::in, set(tvar)::in,
    tvar::in, tvar::in, simple_prog_var_map::in, simple_prog_var_map::out,
    type_domain_map::in, type_domain_map::out) is det.

unify_equal_tvars(TCInfo, Replaced, Replacement, Target,
        !ReplacementMap, !DomainMap) :-
    TCInfo = tconstr_info(VarMap, _, ConstraintMap, VarConstraints, _, _),
    Renaming = map.singleton(Target, Replacement),
    (
        map.search(!.DomainMap, Target, tdomain_any),
        map.search(VarConstraints, Target, ConstraintIds)
    ->
        % Find all variables unified with the target variable.
        map.apply_to_list(ConstraintIds, ConstraintMap, Constraints),
        list.filter_map(to_simple_constraints, Constraints,
            SimpleConstraints0),
        list.condense(SimpleConstraints0, SimpleConstraints),
        list.filter_map(find_unified_var(Target), SimpleConstraints,
            UnifiedVars0),
        list.filter(set.contains(Replaced), UnifiedVars0, _, UnifiedVars),
        % Update the unified variables, and unify with anything unified with
        % those variables.
        list.foldl(update_replacement_map(VarMap, Replacement), UnifiedVars,
            !ReplacementMap),
        set.insert_list(UnifiedVars, Replaced, Replaced1),
        list.foldl2(unify_equal_tvars(TCInfo, Replaced1, Replacement),
            UnifiedVars, !ReplacementMap, !DomainMap)
    ;
        map.search(!.DomainMap, Target, tdomain_singleton(Type0))
    ->
        apply_variable_renaming_to_type(Renaming, Type0, Type),
        map.det_update(Target, tdomain_singleton(Type), !DomainMap)
    ;
        map.search(!.DomainMap, Target, tdomain(Types0))
    ->
        set.map(apply_variable_renaming_to_type(Renaming), Types0, Types),
        map.det_update(Target, tdomain(Types), !DomainMap)
    ;
        % This will only be reached if there are no constraints on the type of
        % a variable. In this case, there can be no variable replacement
        % performed on it. XXX I don't know if this will ever occur.
        true
    ).

%-----------------------------------------------------------------------------%
%
% Constraint solving utility predicates.
%

    % Returns the type variable that is unified with Target in the constraint.
    % Fails if no such variable exists.
    %
:- pred find_unified_var(tvar::in, simple_type_constraint::in, tvar::out)
    is semidet.

find_unified_var(Target, stconstr(LHS, type_variable(RHS, _)), Unified) :-
    (
        LHS = Target,
        RHS = Unified0
    ->
        Unified = Unified0
    ;
        LHS = Unified0,
        RHS = Target
    ->
        Unified = Unified0
    ;
        fail
    ).

:- pred to_simple_constraints(type_constraint::in,
    list(simple_type_constraint)::out) is semidet.

to_simple_constraints(tconstr_conj(Conj), Conj ^ tconstr_simples).
to_simple_constraints(tconstr_disj(_, yes(Conj)), Conj ^ tconstr_simples).

:- pred update_replacement_map(prog_var_map::in, tvar::in, tvar::in,
    simple_prog_var_map::in, simple_prog_var_map::out) is det.

update_replacement_map(VarMap, Replacement, OldVar, !ReplacementMap) :-
    ( bimap.reverse_search(VarMap, ProgVar, OldVar) ->
        map.set(ProgVar, Replacement, !ReplacementMap)
    ;
        true
    ).

:- pred find_type_domain(type_domain_map::in, tvar::in, type_domain::out)
    is det.

find_type_domain(DomainMap, TVar, Domain) :-
    ( map.search(DomainMap, TVar, Domain0) ->
        Domain = Domain0
    ;
        Domain = tdomain_any
    ).

    % If the input type is a type variable, and the type of that type variable
    % is known, return the known type. Otherwise, return the type variable.
    %
:- pred find_type_of_tvar(type_domain_map::in, mer_type::in, mer_type::out)
    is det.

find_type_of_tvar(DomainMap, !Type) :-
    (
        !.Type = type_variable(TVar, _),
        map.search(DomainMap, TVar, tdomain_singleton(KnownType))
    ->
        !:Type = KnownType
    ;
        true
    ).

    % Restrict the domain of the given type variable to the given type. If the
    % variable is not currently in the domain map, insert it. If the variable
    % is restricted to a singleton domain, note this.
    %
:- pred restrict_domain(tvar::in, mer_type::in, type_domain_map::in,
    type_domain_map::out) is det.

restrict_domain(TVar, Type, !DomainMap) :-
    ( map.search(!.DomainMap, TVar, CurrDomain0) ->
        CurrDomain = CurrDomain0
    ;
        CurrDomain = tdomain_any
    ),
    type_domain_intersect(CurrDomain, tdomain(set.make_singleton_set(Type)),
        NewDomain),
    map.set(TVar, NewDomain, !DomainMap).

:- pred type_domain_intersect(type_domain::in, type_domain::in,
    type_domain::out) is det.

type_domain_intersect(DomainA, DomainB, Domain) :-
    (
        DomainA = tdomain_any,
        Domain = DomainB
    ;
        DomainA = tdomain_singleton(_),
        DomainB = tdomain_any,
        Domain = DomainA
    ;
        DomainA = tdomain_singleton(TypeA),
        DomainB = tdomain_singleton(TypeB),
        ( unify_types(TypeA, TypeB, Type) ->
            Domain = tdomain_singleton(Type)
        ;
            Domain = tdomain(set.init)
        )
    ;
        DomainA = tdomain_singleton(TypeA),
        DomainB = tdomain(TypesB),
        % Symmetrical case below.
        set.filter_map(unify_types(TypeA), TypesB, UnifiedTypes),
        ( set.is_singleton(UnifiedTypes, SingletonType) ->
            Domain = tdomain_singleton(SingletonType)
        ;
            Domain = tdomain(UnifiedTypes)
        )
    ;
        DomainA = tdomain(_),
        DomainB = tdomain_any,
        Domain = DomainA
    ;
        DomainA = tdomain(TypesA),
        DomainB = tdomain_singleton(TypeB),
        % Symmetrical case above.
        set.filter_map(unify_types(TypeB), TypesA, UnifiedTypes),
        ( set.is_singleton(UnifiedTypes, SingletonType) ->
            Domain = tdomain_singleton(SingletonType)
        ;
            Domain = tdomain(UnifiedTypes)
        )
    ;
        DomainA = tdomain(TypesA),
        DomainB = tdomain(TypesB),
        set.to_sorted_list(TypesA, TypeListA),
        set.to_sorted_list(TypesB, TypeListB),
        td_list_intersect(TypeListB, TypeListA, TypeList),
        set.sorted_list_to_set(TypeList, Types),
        Domain = tdomain(Types)
    ).

    % Very similar to set.intersect, but will unify equal functors with
    % different type variable parameters - e.g.,
    % yes(type_variable(V_1)) = yes(type_variable(V_2)).
    %
:- pred td_list_intersect(list(mer_type)::in, list(mer_type)::in,
    list(mer_type)::out) is det.

td_list_intersect([], _, []).
td_list_intersect([_ | _], [], []).
td_list_intersect([A | As], [B | Bs], Cs) :-
    ( unify_types(A, B, AB) ->
        td_list_intersect(As, Bs, Cs0),
        Cs = [AB | Cs0]
    ;
        compare(R, A, B),
        (
            R = (<),
            td_list_intersect(As, [B | Bs], Cs)
        ;
            R = (=),
            td_list_intersect(As, Bs, Cs0),
            Cs = [A | Cs0]
        ;
            R = (>),
            td_list_intersect([A | As], Bs, Cs)
        )
    ).

    % Takes two types as input, and returns the most general unification
    % of the types. When two type variables are merged, the first argument
    % takes priority.
    %
:- pred unify_types(mer_type::in, mer_type::in, mer_type::out) is semidet.

unify_types(A, B, Type) :-
    % If two compound types are unified, unify each of their arguments:
    % e.g., yes(type_variable(V_1)) = yes(type_variable(V_2)),
    % and unify any type variable with anything.
    % Fail if types cannot be unified.
    ( B = type_variable(_, _) ->
        Type = A
    ; A = type_variable(_, _) ->
        Type = B
    ;
        (
            A = defined_type(Name, ArgsA, Kind),
            B = defined_type(Name, ArgsB, Kind),
            ( list.same_length(ArgsA, ArgsB) ->
                list.map_corresponding(unify_types, ArgsA, ArgsB, Args),
                Type = defined_type(Name, Args, Kind)
            ;
                fail
            )
        ;
            A = builtin_type(T),
            B = builtin_type(T),
            Type = A
        ;
            A = tuple_type(ArgsA, Kind),
            B = tuple_type(ArgsB, Kind),
            ( list.same_length(ArgsA, ArgsB) ->
                list.map_corresponding(unify_types, ArgsA, ArgsB, Args),
                Type = tuple_type(Args, Kind)
            ;
                fail
            )
        ;
            A = higher_order_type(ArgsA, ResultA, Purity, Lambda),
            B = higher_order_type(ArgsB, ResultB, Purity, Lambda),
            ( list.same_length(ArgsA, ArgsB) ->
                list.map_corresponding(unify_types, ArgsA, ArgsB, Args),
                (
                    ResultA = yes(ResultA1),
                    ResultB = yes(ResultB1),
                    unify_types(ResultA1, ResultB1, Result1),
                    Result = yes(Result1)
                ;
                    ResultA = no,
                    ResultB = no,
                    Result = no
                ),
                Type = higher_order_type(Args, Result, Purity, Lambda)
            ;
                fail
            )
        ;
            A = apply_n_type(TVarA, ArgsA, Kind),
            B = apply_n_type(_, ArgsB, Kind),
            ( list.same_length(ArgsA, ArgsB) ->
                list.map_corresponding(unify_types, ArgsA, ArgsB, Args),
                Type = apply_n_type(TVarA, Args, Kind)
            ;
                fail
            )
        ;
            A = kinded_type(TypeA, Kind),
            B = kinded_type(TypeB, Kind),
            unify_types(TypeA, TypeB, Type)
        )
    ).

    % Like set.union, but treats tdomain_any as the universal domain.
    %
:- pred type_domain_union(type_domain::in, type_domain::in,
    type_domain::out) is det.

type_domain_union(DomainA, DomainB, Domain) :-
    (
        DomainA = tdomain_any,
        Domain = tdomain_any
    ;
        DomainA = tdomain_singleton(_),
        DomainB = tdomain_any,
        Domain = tdomain_any
    ;
        DomainA = tdomain_singleton(TypeA),
        DomainB = tdomain_singleton(TypeB),
        ( TypeA = TypeB ->
            Domain = tdomain_singleton(TypeA)
        ;
            Domain = tdomain(set.from_list([TypeA, TypeB]))
        )
    ;
        DomainA = tdomain_singleton(TypeA),
        DomainB = tdomain(TypesB),
        % Symmetrical case below.
        ( set.empty(TypesB) ->
            Domain = DomainA
        ;
            Domain = tdomain(set.insert(TypesB, TypeA))
        )
    ;
        DomainA = tdomain(_),
        DomainB = tdomain_any,
        Domain = tdomain_any
    ;
        DomainA = tdomain(TypesA),
        DomainB = tdomain_singleton(TypeB),
        % Symmetrical case above.
        ( set.empty(TypesA) ->
            Domain = DomainB
        ;
            Domain = tdomain(set.insert(TypesA, TypeB))
        )
    ;
        DomainA = tdomain(TypesA),
        DomainB = tdomain(TypesB),
        set.union(TypesA, TypesB, Types),
        Domain = tdomain(Types)
    ).

:- pred still_active(conj_type_constraint::in) is semidet.

still_active(ctconstr(_, tconstr_active, _, _, _)).

    % Makes a conjunction of constraints unsatisfiable the conjunction is
    % unsatisfiable, i.e. the domain of any type variable in any of
    % the conjuncts is empty.
    %
:- pred constraint_is_satisfiable(type_domain_map::in,
    list(simple_type_constraint)::in) is semidet.

constraint_is_satisfiable(DomainMap, SimpleConstraints) :-
    list.map(tvars_in_simple_constraint, SimpleConstraints, TVars0),
    list.condense(TVars0, TVars),
    list.filter_map(map.search(DomainMap), TVars, Domains),
    list.all_true(non_empty_domain, Domains).

:- pred non_empty_domain(type_domain::in) is semidet.

non_empty_domain(tdomain_any).
non_empty_domain(tdomain_singleton(_)).
non_empty_domain(tdomain(D)) :-
    set.non_empty(D).

    % Checks whether the given variable domain is compatible with the
    % domain map.
    %
:- pred domain_map_unchanged(type_domain_map::in, pair(tvar, type_domain)::in)
    is semidet.

domain_map_unchanged(DomainMap, (TVar - Domain)) :-
    map.search(DomainMap, TVar, Domain0),
    equal_domain(Domain0, Domain).

:- pred equal_domain(type_domain::in, type_domain::in) is semidet.

equal_domain(tdomain_any, tdomain_any).
equal_domain(tdomain_singleton(A), tdomain_singleton(B)) :-
    unify_types(A, B, _).
equal_domain(tdomain(A), tdomain(B)) :-
    (
        set.count(A, C),
        set.count(B, C)
    ->
        list.map_corresponding(unify_types,
            set.to_sorted_list(A), set.to_sorted_list(B), _)
    ;
        fail
    ).

:- pred has_empty_domain(pair(tvar, type_domain)::in, tvar::out) is semidet.

has_empty_domain(TVar - tdomain(Domain), TVar) :-
    set.empty(Domain).

    % Checks if a variable which was not previously known to have a singleton
    % domain has a singleton domain.
    %
:- pred has_singleton_domain(type_domain_map::in, tvar::in) is semidet.

has_singleton_domain(DomainMap, TVar) :-
    map.search(DomainMap, TVar, tdomain(Domain)),
    set.is_singleton(Domain, _).

:- pred is_singleton_domain(type_domain::in, mer_type::out) is semidet.

is_singleton_domain(tdomain_singleton(Type), Type).
is_singleton_domain(tdomain(Domain), Type) :-
    set.is_singleton(Domain, Type).

:- pred update_singleton_domain(tvar::in, type_domain_map::in,
    type_domain_map::out) is det.

update_singleton_domain(TVar, !DomainMap) :-
    (
        map.search(!.DomainMap, TVar, tdomain(Domain)),
        set.is_singleton(Domain, Type)
    ->
        map.set(TVar, tdomain_singleton(Type), !DomainMap)
    ;
        true
    ).

    % Returns all type variables present in a type constraint.
    %
:- pred tvars_in_constraint(type_constraint::in, list(tvar)::out) is det.

tvars_in_constraint(tconstr_conj(ctconstr(Constraints, _, _, _, _)), TVars) :-
    list.map(tvars_in_simple_constraint, Constraints, TVarLists),
    list.condense(TVarLists, TVars).
tvars_in_constraint(tconstr_disj(Disjuncts0, _), TVars) :-
    list.map(get_constraints_from_conj, Disjuncts0, Disjuncts),
    list.condense(Disjuncts, Constraints),
    list.map(tvars_in_simple_constraint, Constraints, TVarLists),
    list.condense(TVarLists, TVars).

:- pred tvars_in_simple_constraint(simple_type_constraint::in,
    list(tvar)::out) is det.

tvars_in_simple_constraint(stconstr(TVar, Type), [TVar | TVars]) :-
    prog_type.type_vars(Type, TVars).

:- pred constraint_has_no_solutions(type_domain_map::in) is semidet.

constraint_has_no_solutions(DomainMap) :-
    list.member(tdomain(set.init), map.values(DomainMap)).

:- pred constraint_has_one_solution(type_domain_map::in) is semidet.

constraint_has_one_solution(DomainMap) :-
    list.map(is_singleton_domain, map.values(DomainMap), _).

:- pred constraint_has_multiple_solutions(type_domain_map::in, tvar::out,
    list(type_domain)::out) is semidet.

constraint_has_multiple_solutions(DomainMap, Var, Domains) :-
    map.to_assoc_list(DomainMap, DomainMap1),
    list.filter(has_ambiguous_domain, DomainMap1, AmbigDomains0),
    list.sort(domain_size_compare, AmbigDomains0, [(Var - Domain0) | _]),
    Domain0 = tdomain(Domain1),
    Domains = set.to_sorted_list(set.map(to_singleton_type_domain, Domain1)).

:- pred has_ambiguous_domain(pair(tvar, type_domain)::in) is semidet.

has_ambiguous_domain((_ - tdomain(Dom))) :-
    set.count(Dom, Size),
    Size > 1.

    % Compares the domain size of two domains. The variables corresponding
    % to the domains are ignored. Should only be used to compare
    % domains that are not singleton or undefined.
    %
:- pred domain_size_compare(pair(tvar, type_domain)::in,
    pair(tvar, type_domain)::in, comparison_result::out) is det.

domain_size_compare((_ - A), (_ - B), Result) :-
    (
        A = tdomain(D1),
        B = tdomain(D2)
    ->
        list.length(set.to_sorted_list(D1), L1),
        list.length(set.to_sorted_list(D2), L2),
        compare(Result, L1, L2)
    ;
        Result = (=)
    ).

:- func to_singleton_type_domain(mer_type) = type_domain.

to_singleton_type_domain(Type) = tdomain_singleton(Type).

    % If the program variable is not in the vartypes map, assigns it to
    % a fresh type variable and inserts it into the map.
    %
:- pred add_unused_prog_var(type_constraint_info::in, prog_var::in,
    vartypes::in, vartypes::out) is det.

add_unused_prog_var(TCInfo, Var, !Vartypes) :-
    ( is_in_vartypes(!.Vartypes, Var) ->
        true
    ;
        bimap.lookup(TCInfo ^ tconstr_var_map, Var, TVar),
        add_var_type(Var, tvar_to_type(TVar), !Vartypes)
    ).

:- pred get_constraints_from_conj(conj_type_constraint::in,
    list(simple_type_constraint)::out) is det.

get_constraints_from_conj(Conj, Conj ^ tconstr_simples).

    % Merges two type constraints, which should be equal except possibly
    % for the activity of their disjuncts, into one type constraint. The
    % disjuncts of the result constraint are active if the respective
    % disjuncts of either input constraint are active.
    %
:- pred merge_type_constraints(type_constraint::in, type_constraint::in,
    type_constraint::out) is det.

merge_type_constraints(A, B, Result) :-
    (
        A = tconstr_conj(ConjA),
        ConjsA = [ConjA]
    ;
        A = tconstr_disj(ConjsA, _)
    ),
    (
        B = tconstr_conj(ConjB),
        ConjsB = [ConjB]
    ;
        B = tconstr_disj(ConjsB, _)
    ),
    list.map_corresponding(merge_type_constraints2, ConjsA, ConjsB, Conjs),
    ( Conjs = [SingletonConj] ->
        Result = tconstr_conj(SingletonConj)
    ; list.filter(still_active, Conjs, [SingletonConj]) ->
        Result = tconstr_disj(Conjs, yes(SingletonConj))
    ;
        Result = tconstr_disj(Conjs, no)
    ).

:- pred merge_type_constraints2(conj_type_constraint::in,
    conj_type_constraint::in, conj_type_constraint::out) is det.

merge_type_constraints2(A, B, Result) :-
    (
        A ^ tconstr_activity = tconstr_unsatisfiable,
        B ^ tconstr_activity = tconstr_unsatisfiable
    ->
        Result = A
    ;
        Result = A ^ tconstr_activity := tconstr_active
    ).

%-----------------------------------------------------------------------------%
%
% Error diagnosis.
%

    % If the list of type constraints contains more than one predicate call
    % constraint, return an error message describing the ambiguity and one
    % of the predicate call constraints (chosen arbitrarily). Otherwise, fail.
    %
:- pred diagnose_ambig_pred_error(pred_env::in, list(conj_type_constraint)::in,
    error_msg::out) is semidet.

diagnose_ambig_pred_error(PredEnv, Conjunctions, Msg) :-
    conj_constraint_get_context(head(Conjunctions), Context),
    list.filter_map(pred_constraint_info, Conjunctions, AmbigPredData),
    \+ list.all_same(assoc_list.values(AmbigPredData)),
    list.map(ambig_pred_error_message(PredEnv), AmbigPredData, Components),
    Pieces = [always([words("Ambiguous predicate call."),
        words("Possible predicates include:"), nl_indent_delta(2)])
        | Components],
    Msg = simple_msg(Context, Pieces).

:- pred ambig_pred_error_message(pred_env::in, pair(goal_id, pred_id)::in,
    error_msg_component::out) is det.

ambig_pred_error_message(PredEnv, (_ - PredId), Component) :-
    % XXX Should use describe_one_pred_name.
    predicate_table_get_preds(PredEnv, Preds),
    map.lookup(Preds, PredId, PredInfo),
    Name = pred_info_name(PredInfo),
    Arity = pred_info_orig_arity(PredInfo),
    pred_info_get_context(PredInfo, Context),
    LineNumber = term.context_line(Context),
    FileName = term.context_file(Context),
    Component = always([fixed(Name), suffix("/"), suffix(int_to_string(Arity)),
        prefix("("), words(FileName), suffix(": "), int_fixed(LineNumber),
        suffix(")")]).

:- pred pred_constraint_info(conj_type_constraint::in,
    pair(goal_id, pred_id)::out) is semidet.

pred_constraint_info(Constraint, Path - PredId) :-
    Constraint = ctconstr(_, tconstr_active, _, yes(Path), yes(PredId)).

    % Creates an error message describing why a variable is unsatisfiable.
    % This is done by finding all minimal unsatisfiable subsets of the
    % constraints on the type of the variable, then finding the constraints
    % that are present in all of these subsets.
    %
:- pred diagnose_unsatisfiability_error(type_constraint_info::in,
    prog_context::in, prog_varset::in, tvar::in,
    error_msg::out) is det.

diagnose_unsatisfiability_error(TCInfo, Context, ProgVarSet, TypeVar, Msg) :-
    TCInfo = tconstr_info(VarMap, _, ConstraintMap, VarConstraints,
        TVarSet, _),
    map.lookup(VarConstraints, TypeVar, ConstraintIds),
    set.insert_list(ConstraintIds, set.init, ConstraintSet),
    min_unsat_constraints(TCInfo, set.init, ConstraintSet, [], MinUnsats),
    list.map(error_from_one_min_set(ConstraintMap), MinUnsats, MinUnsatPieces),
    zip_single([suffix(") or"), nl, prefix("(")],
        MinUnsatPieces, ErrorLocations0),
    list.condense(ErrorLocations0, ErrorLocations),
    ( bimap.reverse_search(VarMap, ProgVar, TypeVar) ->
        VarName = mercury_var_to_string(ProgVarSet, no, ProgVar),
        VarKind = "program"
    ;
        VarName = mercury_var_to_string(TVarSet, yes, TypeVar),
        VarKind = "type"
    ),
    Msg = simple_msg(Context,
        [always([words("Conflicting type assignments for the"),
        fixed(VarKind), words("variable"), words(VarName), nl,
        words("The problem is most likely due to one of the following"),
        words("sets of goals"), nl, prefix("(")] ++ ErrorLocations ++
        [suffix(")"), nl])]).

:- pred error_from_one_min_set(type_constraint_map::in,
    set(type_constraint_id)::in, list(format_component)::out) is det.

error_from_one_min_set(ConstraintMap, MinUnsatSet, Components) :-
    set.to_sorted_list(MinUnsatSet, MinUnsatList),
    map.apply_to_list(MinUnsatList, ConstraintMap, Constraints),
    list.filter_map(get_first_disjunct, Constraints, ConjConstraints),
    list.map(conj_constraint_get_context, ConjConstraints, Contexts),
    list.map(context_to_string, Contexts, ContextStrings),
    Components = list_to_pieces(ContextStrings).

    % Uses the min_unsat1 algorithm
    % (www.cs.mu.oz.au/~pjs/papers/ppdp2003b.ps.gz)
    % to find all minimal unsatisfiable subsets
    % of the constraints on the types of variables.
    %
:- pred min_unsat_constraints(type_constraint_info::in,
    type_constraint_set::in, type_constraint_set::in,
    list(type_constraint_set)::in, list(type_constraint_set)::out) is det.

min_unsat_constraints(TCInfo, D, P, !MinUnsats) :-
    % XXX What are D and P?
    TCInfo = tconstr_info(VarMap, _, ConstraintMap, VarConstraints0,
        TVarSet, _),
    set.union(P, D, Union),
    trace [compile_time(flag("type_error_diagnosis")), io(!IO)] (
        list.map(string.int_to_string, set.to_sorted_list(Union), Ids),
        io.print("\n    Constraints " ++ string.join_list(", ", Ids) ++ "\n",
            !IO)
    ),
    % Remove all constraints which are not part of the subset currently
    % being examined.
    list.foldl(map.det_transform_value(list.filter(set.contains(Union))),
        map.keys(VarConstraints0), VarConstraints0, VarConstraints),
    map.select(ConstraintMap, Union, UnionConstraintMap),
    Constraint = tconstr_info(VarMap, counter.init(0), UnionConstraintMap,
        VarConstraints, TVarSet, []),

    solve_constraint_labeling(TVarSet, VarConstraints, UnionConstraintMap,
        map.init, map.init, tconstr_solution(_, _, Success)),
    (
        Success = no,
        set.fold3(next_min_unsat(Constraint), P, D, NewD, P, _, !MinUnsats),
        ( list.all_false(set.superset(NewD), !.MinUnsats) ->
            !:MinUnsats = [NewD | !.MinUnsats]
        ;
            true
        )
    ;
        Success = yes
    ).

:- pred next_min_unsat(type_constraint_info::in, type_constraint_id::in,
    type_constraint_set::in, type_constraint_set::out,
    type_constraint_set::in, type_constraint_set::out,
    list(type_constraint_set)::in, list(type_constraint_set)::out) is det.

next_min_unsat(Constraint, C, !D, !P, !MinUnsats) :-
    set.delete(C, !P),
    min_unsat_constraints(Constraint, !.D, !.P, !MinUnsats),
    set.insert(C, !D).

:- pred add_message_to_spec(error_msg::in, type_constraint_info::in,
    type_constraint_info::out) is det.

add_message_to_spec(ErrMsg, !TCInfo) :-
    Spec = error_spec(severity_error, phase_type_check, [ErrMsg]),
    !TCInfo ^ tconstr_error_specs := [Spec | !.TCInfo ^ tconstr_error_specs].

:- pred context_to_string(prog_context::in, string::out) is det.

context_to_string(Context, String) :-
    LineNumber = string.int_to_string(term.context_line(Context)),
    FileName = term.context_file(Context),
    String = "[" ++ FileName ++ ": " ++ LineNumber ++ "]".

:- pred conj_constraint_get_context(conj_type_constraint::in,
    prog_context::out) is det.

conj_constraint_get_context(Constraint, Constraint ^ tconstr_context).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
%
% Constraint generation.
%

    % Turn a goal expression to a constraint on the types of variable
    % appearing within that goal, then update all relevant maps with the
    % information in the new constraint.
    %
:- pred goal_to_constraint(tconstr_environment::in, hlds_goal::in,
    type_constraint_info::in, type_constraint_info::out) is det.

goal_to_constraint(Environment, Goal, !TCInfo) :-
    % Environment = tconstr_environment(_, _, FuncEnv, PredEnv),
    Goal = hlds_goal(GoalExpr, GoalInfo),
    (
        GoalExpr = unify(_, _, _, _, _),
        unify_goal_to_constraint(Environment, GoalExpr, GoalInfo, !TCInfo)
    ;
        GoalExpr = plain_call(_, _, _, _, _, _),
        plain_call_goal_to_constraint(Environment, GoalExpr, GoalInfo, !TCInfo)
    ;
        GoalExpr = call_foreign_proc(_, _, _, _, _, _, _),
        foreign_proc_goal_to_constraint(Environment, GoalExpr, GoalInfo,
            !TCInfo)
    ;
        GoalExpr = generic_call(_, _, _, _, _),
        generic_call_goal_to_constraint(Environment, GoalExpr, GoalInfo,
            !TCInfo)
    ;
        GoalExpr = conj(_, Goals),
        list.foldl(goal_to_constraint(Environment), Goals, !TCInfo)
    ;
        GoalExpr = disj(Goals),
        list.foldl(goal_to_constraint(Environment), Goals, !TCInfo)
    ;
        GoalExpr = negation(SubGoal),
        goal_to_constraint(Environment, SubGoal, !TCInfo)
    ;
        GoalExpr = scope(_, SubGoal),
        goal_to_constraint(Environment, SubGoal, !TCInfo)
    ;
        GoalExpr = if_then_else(_, Cond, Then, Else),
        goal_to_constraint(Environment, Cond, !TCInfo),
        goal_to_constraint(Environment, Then, !TCInfo),
        goal_to_constraint(Environment, Else, !TCInfo)
    ;
        GoalExpr = switch(_, _, Cases),
        list.map(get_case_goal, Cases, Goals),
        list.foldl(goal_to_constraint(Environment), Goals, !TCInfo)
    ;
        GoalExpr = shorthand(_),
        shorthand_goal_to_constraint(Environment, GoalExpr, GoalInfo, !TCInfo)
    ).

    % Transform a unification constraint into an assignment of types
    % to the variables being unified.
    %
:- pred unify_goal_to_constraint(tconstr_environment::in,
    hlds_goal_expr::in(goal_expr_unify), hlds_goal_info::in,
    type_constraint_info::in, type_constraint_info::out) is det.

unify_goal_to_constraint(Environment, GoalExpr, GoalInfo, !TCInfo) :-
    Context = goal_info_get_context(GoalInfo),
    GoalExpr = unify(L, RHS, _, _, _),
    get_var_type(L, LTVar, !TCInfo),
    (
        RHS = rhs_var(R),
        get_var_type(R, RTVar, !TCInfo),
        Constraints = [ctconstr([stconstr(LTVar, tvar_to_type(RTVar))],
            tconstr_active, Context, no, no)],
        RelevantTVars = [LTVar, RTVar]
    ;
        RHS = rhs_functor(ConsId, _, Args),
        (
            builtin_atomic_type(ConsId, Builtin)
        ->
            SimpleConstraint = stconstr(LTVar, builtin_type(Builtin)),
            Constraints = [ctconstr([SimpleConstraint], tconstr_active,
                Context, no, no)],
            RelevantTVars = [LTVar]
        ;
            ConsId = cons(Name, Arity, _TypeCtor),
            % The _TypeCtor field is not meaningful yet.
            Arity = list.length(Args)
        ->
            list.map_foldl(get_var_type, Args, ArgTypeVars, !TCInfo),
            % If it is a data constructor, create a disjunction constraint
            % with each possible type of the constructor.
            Environment = tconstr_environment(_, _, FuncEnv, PredEnv),
            ( search_cons_table(FuncEnv, ConsId, ConsDefns) ->
                list.map_foldl(
                    functor_unif_constraint(LTVar, ArgTypeVars, GoalInfo),
                    ConsDefns, TypeConstraints, !TCInfo)
            ;
                TypeConstraints = []
            ),
            % If it is a closure constructor, create a disjunction
            % constraint for each predicate it could refer to.
            predicate_table_lookup_sym(PredEnv, may_be_partially_qualified,
                Name, PredIds),
            (
                PredIds = [_ | _],
                predicate_table_get_preds(PredEnv, Preds),
                list.filter_map_foldl(
                    ho_pred_unif_constraint(Preds, GoalInfo, LTVar,
                        ArgTypeVars),
                    PredIds, PredConstraints, !TCInfo)
            ;
                PredIds = [],
                PredConstraints = []
            ),
            Constraints = TypeConstraints ++ PredConstraints,
            (
                Constraints = [],
                ErrMsg = simple_msg(Context, [always([
                    words("The constructor"),
                    sym_name_and_arity(Name / Arity),
                    words("has not been defined")])]),
                add_message_to_spec(ErrMsg, !TCInfo)
            ;
                Constraints = [_ | _]
            ),
            RelevantTVars = [LTVar | ArgTypeVars]
        ;
            Pieces = [words("The given type is not supported"),
                words("by constraint-based type checking.")],
            ErrMsg = simple_msg(Context, [always(Pieces)]),
            add_message_to_spec(ErrMsg, !TCInfo),
            RelevantTVars = [],
            Constraints = []
        )
    ;
        RHS = rhs_lambda_goal(Purity, _, PredOrFunc, EvalMethod, _, Args,
            _, _, LambdaGoal),
        list.map_foldl(get_var_type, Args, ArgTVars, !TCInfo),
        ArgTypes = list.map(tvar_to_type, ArgTVars),
        construct_higher_order_type(Purity, PredOrFunc, EvalMethod,
            ArgTypes, LambdaType),
        Constraints = [ctconstr([stconstr(LTVar, LambdaType)],
            tconstr_active, Context, no, no)],
        RelevantTVars = [LTVar | ArgTVars],
        goal_to_constraint(Environment, LambdaGoal, !TCInfo)
    ),
    add_type_constraint(Constraints, RelevantTVars, !TCInfo).

:- pred plain_call_goal_to_constraint(tconstr_environment::in,
    hlds_goal_expr::in(goal_expr_plain_call), hlds_goal_info::in,
    type_constraint_info::in, type_constraint_info::out) is det.

plain_call_goal_to_constraint(Environment, GoalExpr, GoalInfo, !TCInfo) :-
    Environment = tconstr_environment(_, _, _FuncEnv, PredEnv),
    GoalExpr = plain_call(_, _, Args, _, _, Name),
    % Transform a call to variable assignments of the variables
    % used in the call.
    predicate_table_lookup_pred_sym(PredEnv, may_be_partially_qualified,
        Name, PredIds0),
    predicate_table_get_preds(PredEnv, Preds),
    list.filter(pred_has_arity(Preds, list.length(Args)), PredIds0, PredIds),
    list.map_foldl(get_var_type, Args, ArgTVars, !TCInfo),
    list.map2_foldl(pred_call_constraint(Preds, GoalInfo, ArgTVars),
        PredIds, Constraints, PredTVars, !TCInfo),
    list.condense([ArgTVars | PredTVars], TVars),
    add_type_constraint(Constraints, TVars, !TCInfo).

:- pred foreign_proc_goal_to_constraint(tconstr_environment::in,
    hlds_goal_expr::in(goal_expr_foreign_proc), hlds_goal_info::in,
    type_constraint_info::in, type_constraint_info::out) is det.

foreign_proc_goal_to_constraint(Environment, GoalExpr, GoalInfo, !TCInfo) :-
    GoalExpr = call_foreign_proc(_, PredId, _, ForeignArgs, _, _, _),
    Context = goal_info_get_context(GoalInfo),
    ArgVars = list.map(foreign_arg_var, ForeignArgs),
    ArgTypes0 = list.map(foreign_arg_type, ForeignArgs),
    predicate_table_get_preds(Environment ^ pred_env, Preds),
    ( map.search(Preds, PredId, PredInfo) ->
        pred_info_get_typevarset(PredInfo, PredTVarSet),
        prog_data.tvarset_merge_renaming(!.TCInfo ^ tconstr_tvarset,
            PredTVarSet, NewTVarSet, TVarRenaming),
        !TCInfo ^ tconstr_tvarset := NewTVarSet,
        prog_type_subst.apply_variable_renaming_to_type_list(TVarRenaming,
            ArgTypes0, ArgTypes),
        list.foldl_corresponding(variable_assignment_constraint(Context),
            ArgVars, ArgTypes, !TCInfo)
    ;
        unexpected($module, $pred, "cannot find pred_info for foreign_proc")
    ).

:- pred generic_call_goal_to_constraint(tconstr_environment::in,
    hlds_goal_expr::in(goal_expr_generic_call), hlds_goal_info::in,
    type_constraint_info::in, type_constraint_info::out) is det.

generic_call_goal_to_constraint(Environment, GoalExpr, GoalInfo, !TCInfo) :-
    GoalExpr = generic_call(Details, Vars, _, _, _),
    Context = goal_info_get_context(GoalInfo),
    list.map_foldl(get_var_type, Vars, ArgTVars, !TCInfo),
    ArgTypes = list.map(tvar_to_type, ArgTVars),
    (
        Details = higher_order(CallVar, Purity, Kind, _),
        (
            Kind = pf_predicate,
            HOType = higher_order_type(ArgTypes, no, Purity, lambda_normal)
        ;
            Kind = pf_function,
            varset.new_var(FunctionTVar, !.TCInfo ^ tconstr_tvarset,
                NewTVarSet),
            !TCInfo ^ tconstr_tvarset := NewTVarSet,
            HOType = apply_n_type(FunctionTVar, ArgTypes, kind_star)
        ),
        variable_assignment_constraint(Context, CallVar, HOType, !TCInfo)
    ;
        % Class methods are handled by looking up the method number in the
        % class' method list.
        Details = class_method(_, MethodNum, ClassId, _),
        ClassId = class_id(Name, Arity),
        ( map.search(Environment ^ class_env, ClassId, ClassDefn) ->
            (
                list.index0(ClassDefn ^ class_hlds_interface, MethodNum,
                    Method)
            ->
                Method = hlds_class_proc(PredId, _),
                predicate_table_get_preds(Environment ^ pred_env, Preds),
                ( pred_has_arity(Preds, list.length(Vars), PredId) ->
                    pred_call_constraint(Preds, GoalInfo, ArgTVars, PredId,
                        Constraint, PredTVars, !TCInfo),
                    list.append(ArgTVars, PredTVars, TVars),
                    add_type_constraint([Constraint], TVars, !TCInfo)
                ;
                    Pieces = [words("Incorrect number of arguments"),
                        words("provided to method"), int_fixed(MethodNum),
                        words("of typeclass"),
                        sym_name_and_arity(Name / Arity)],
                    ErrMsg = simple_msg(Context, [always(Pieces)]),
                    add_message_to_spec(ErrMsg, !TCInfo)
                )
            ;
                Pieces = [words("The typeclass"),
                    sym_name_and_arity(Name / Arity),
                    words("does not have the given method.")],
                ErrMsg = simple_msg(Context, [always(Pieces)]),
                add_message_to_spec(ErrMsg, !TCInfo)
            )
        ;
            Pieces = [words("The typeclass"),
                sym_name_and_arity(Name / Arity),
                words("is undefined.")],
            ErrMsg = simple_msg(Context, [always(Pieces)]),
            add_message_to_spec(ErrMsg, !TCInfo)
        )
    ;
        Details = event_call(Name),
        ( event_arg_types(Environment ^ event_env, Name, _ArgTypes0) ->
            Pieces = [words("Event calls are not yet supported"),
                words("by constraint-based typechecking.")],
            ErrMsg = simple_msg(Context, [always(Pieces)]),
            add_message_to_spec(ErrMsg, !TCInfo)
        ;
            Pieces = [words("There is not event named"), words(Name)],
            ErrMsg = simple_msg(Context, [always(Pieces)]),
            add_message_to_spec(ErrMsg, !TCInfo)
        )
    ;
        % Casts do not contain any type information.
        Details = cast(_)
    ).

:- pred shorthand_goal_to_constraint(tconstr_environment::in,
    hlds_goal_expr::in(goal_expr_shorthand), hlds_goal_info::in,
    type_constraint_info::in, type_constraint_info::out) is det.

shorthand_goal_to_constraint(Environment, GoalExpr, GoalInfo, !TCInfo) :-
    GoalExpr = shorthand(Shorthand),
    (
        Shorthand = atomic_goal(GoalType, Outer, Inner, _,
            Main, Alternatives, _),
        % Atomic goals are handled by forcing their inner arguments
        % to be of type stm_atomic_type, their outer arguments to be
        % of type stm_atomic_type or io_state_type, depending on the type
        % of atomic goal. The transaction goals are handled by recursive
        % calls to goal_to_constraint.

        Context = goal_info_get_context(GoalInfo),
        % Inner variable handling (simple assignment).
        Inner = atomic_interface_vars(InnerInitVar, InnerFinalVar),
        variable_assignment_constraint(Context, InnerInitVar, stm_atomic_type,
            !TCInfo),
        variable_assignment_constraint(Context, InnerFinalVar, stm_atomic_type,
            !TCInfo),
        % Create possible constraints on outer variables.
        Outer = atomic_interface_vars(OuterInitVar, OuterFinalVar),
        get_var_type(OuterInitVar, OuterInit, !TCInfo),
        get_var_type(OuterFinalVar, OuterFinal, !TCInfo),
        InitStmConstraint = ctconstr([stconstr(OuterInit, stm_atomic_type)],
            tconstr_active, Context, no, no),
        InitIOConstraint = ctconstr([stconstr(OuterInit, io_state_type)],
            tconstr_active, Context, no, no),
        FinalStmConstraint = ctconstr([stconstr(OuterFinal, stm_atomic_type)],
            tconstr_active, Context, no, no),
        FinalIOConstraint = ctconstr([stconstr(OuterFinal, io_state_type)],
            tconstr_active, Context, no, no),
        % Determine which constraints should be applied to outer variables..
        (
            GoalType = unknown_atomic_goal_type,
            add_type_constraint([InitStmConstraint, InitIOConstraint],
                [OuterInit], !TCInfo),
            add_type_constraint([FinalStmConstraint, FinalIOConstraint],
                [OuterFinal], !TCInfo)
        ;
            GoalType = top_level_atomic_goal,
            add_type_constraint([InitIOConstraint], [OuterInit], !TCInfo),
            add_type_constraint([FinalIOConstraint], [OuterFinal], !TCInfo)
        ;
            GoalType = nested_atomic_goal,
            add_type_constraint([InitStmConstraint], [OuterInit], !TCInfo),
            add_type_constraint([FinalStmConstraint], [OuterFinal], !TCInfo)
        ),
        % Recursively evaluate transaction goals.
        list.foldl(goal_to_constraint(Environment), [Main | Alternatives],
            !TCInfo)
    ;
        Shorthand = try_goal(MaybeIO, _ResultVar, SubGoal),
        Context = goal_info_get_context(GoalInfo),
        (
            MaybeIO = yes(try_io_state_vars(IOVarA, IOVarB)),
            get_var_type(IOVarA, InitA, !TCInfo),
            get_var_type(IOVarB, InitB, !TCInfo),
            ConstraintA = ctconstr([stconstr(InitA, io_state_type)],
                tconstr_active, Context, no, no),
            ConstraintB = ctconstr([stconstr(InitB, io_state_type)],
                tconstr_active, Context, no, no),
            add_type_constraint([ConstraintA], [InitA], !TCInfo),
            add_type_constraint([ConstraintB], [InitB], !TCInfo)
        ;
            MaybeIO = no
        ),
        goal_to_constraint(Environment, SubGoal, !TCInfo)
    ;
        Shorthand = bi_implication(GoalA, GoalB),
        goal_to_constraint(Environment, GoalA, !TCInfo),
        goal_to_constraint(Environment, GoalB, !TCInfo)
    ).

    % Creates a constraint from the information stored in a predicate
    % definition. This may only be called if the number of arguments given
    % is equal to the arity of the predicate.
    %
:- pred pred_call_constraint(pred_table::in, hlds_goal_info::in,
    list(tvar)::in, pred_id::in, conj_type_constraint::out, list(tvar)::out,
    type_constraint_info::in, type_constraint_info::out) is det.

pred_call_constraint(PredTable, Info, ArgTVars, PredId, Constraint, TVars,
        !TCInfo) :-
    Constraint = ctconstr(Constraints, tconstr_active, Context,
        yes(GoalId), yes(PredId)),
    Context = goal_info_get_context(Info),
    GoalId = goal_info_get_goal_id(Info),
    ( map.search(PredTable, PredId, PredInfo) ->
        pred_info_get_arg_types(PredInfo, PredArgTypes0),
        pred_info_get_typevarset(PredInfo, PredTVarSet),
        prog_data.tvarset_merge_renaming(!.TCInfo ^ tconstr_tvarset,
            PredTVarSet, NewTVarSet, TVarRenaming),
        !TCInfo ^ tconstr_tvarset := NewTVarSet,
        prog_type_subst.apply_variable_renaming_to_type_list(TVarRenaming,
            PredArgTypes0, PredArgTypes),
        Constraints = list.map_corresponding(create_stconstr, ArgTVars,
            PredArgTypes),
        prog_type.type_vars_list(PredArgTypes, TVars)
    ;
        Pieces = [words("The predicate with id"),
            int_fixed(pred_id_to_int(PredId)),
            words("has not been defined.")],
        ErrMsg = simple_msg(Context, [always(Pieces)]),
        add_message_to_spec(ErrMsg, !TCInfo),
        TVars = [],
        Constraints = []
    ).

    % Creates a constraint from a higher-order unification, e.g,
    % :- pred add(int, int, int), X = add(Y) ->
    % X :: pred(int, int), Y :: int.
    % Fails if the number of arguments supplied to the predicate is greater
    % than its arity.
    %
:- pred ho_pred_unif_constraint(pred_table::in, hlds_goal_info::in, tvar::in,
    list(tvar)::in, pred_id::in, conj_type_constraint::out,
    type_constraint_info::in, type_constraint_info::out) is semidet.

ho_pred_unif_constraint(PredTable, Info, LHSTVar, ArgTVars, PredId, Constraint,
        !TCInfo) :-
    Constraint = ctconstr(Constraints, tconstr_active, Context,
        yes(GoalId), yes(PredId)),
    Context = goal_info_get_context(Info),
    GoalId = goal_info_get_goal_id(Info),
    ( map.search(PredTable, PredId, PredInfo) ->
        pred_info_get_arg_types(PredInfo, PredArgTypes0),
        pred_info_get_typevarset(PredInfo, PredTVarSet),
        pred_info_get_purity(PredInfo, Purity),
        PredOrFunc = pred_info_is_pred_or_func(PredInfo),
        prog_data.tvarset_merge_renaming(!.TCInfo ^ tconstr_tvarset,
            PredTVarSet, NewTVarSet, TVarRenaming),
        !TCInfo ^ tconstr_tvarset := NewTVarSet,
        prog_type_subst.apply_variable_renaming_to_type_list(TVarRenaming,
            PredArgTypes0, PredArgTypes),
        (
            list.split_list(list.length(ArgTVars), PredArgTypes, HOArgTypes,
                LambdaTypes)
        ->
            ArgConstraints = list.map_corresponding(create_stconstr,
                ArgTVars, HOArgTypes),
            (
                PredOrFunc = pf_predicate,
                LHSConstraint = stconstr(LHSTVar, higher_order_type(
                    LambdaTypes, no, Purity, lambda_normal))
            ;
                PredOrFunc = pf_function,
                list.split_list(list.length(LambdaTypes) - 1, LambdaTypes,
                    LambdaTypes1, [ReturnType]),
                (
                    LambdaTypes1 = [],
                    LHSConstraint = stconstr(LHSTVar, ReturnType)
                ;
                    LambdaTypes1 = [_ | _],
                    LHSConstraint = stconstr(LHSTVar, higher_order_type(
                        LambdaTypes1, yes(ReturnType), Purity, lambda_normal))
                )
            ),
            Constraints = [LHSConstraint | ArgConstraints]
        ;
            fail
        )
    ;
        Pieces = [words("The predicate with id"),
            int_fixed(pred_id_to_int(PredId)),
            words("has not been defined.")],
        ErrMsg = simple_msg(Context, [always(Pieces)]),
        add_message_to_spec(ErrMsg, !TCInfo),
        Constraints = []
    ).

    % Creates a constraint from the assignment of a type to a program variable.
    %
:- pred variable_assignment_constraint(prog_context::in, prog_var::in,
    mer_type::in, type_constraint_info::in, type_constraint_info::out) is det.

variable_assignment_constraint(Context, Var, Type, !TCInfo) :-
    prog_type.type_vars(Type, TypeVariables),
    get_var_type(Var, TVar, !TCInfo),
    Constraint = ctconstr([stconstr(TVar, Type)], tconstr_active, Context,
        no, no),
    add_type_constraint([Constraint], [TVar | TypeVariables], !TCInfo).

    % Create a conjunction of type constraints from a functor unification goal.
    % The LHS variable is constrained to be of the result type, and each RHS
    % variable is constrained to be of the appropriate argument type. May
    % only be called if the arity of the functor is equal to the number of
    % arguments given to it.
    %
:- pred functor_unif_constraint(tvar::in, list(tvar)::in, hlds_goal_info::in,
    hlds_cons_defn::in, conj_type_constraint::out, type_constraint_info::in,
    type_constraint_info::out) is det.

functor_unif_constraint(LTVar, ArgTVars, Info, ConsDefn, Constraints,
        !TCInfo) :-
    ConsDefn = hlds_cons_defn(TypeCtor, FunctorTVarSet, TypeParams0, _, _, _,
        FuncArgs, _),
    Context = goal_info_get_context(Info),
    GoalId = goal_info_get_goal_id(Info),
    % Find the types of each argument and the result type, given a renaming
    % of type variables.
    list.map(get_ctor_arg_type, FuncArgs, FuncArgTypes0),
    prog_data.tvarset_merge_renaming(!.TCInfo ^ tconstr_tvarset,
        FunctorTVarSet, NewTVarSet, TVarRenaming),
    !TCInfo ^ tconstr_tvarset := NewTVarSet,
    prog_type_subst.apply_variable_renaming_to_tvar_list(TVarRenaming,
        TypeParams0, TypeParams),
    prog_type_subst.apply_variable_renaming_to_type_list(TVarRenaming,
        FuncArgTypes0, FuncArgTypes),
    Params = list.map(tvar_to_type, TypeParams),
    prog_type.construct_type(TypeCtor, Params, ResultType),
    LHS_Constraint = stconstr(LTVar, ResultType),
    RHS_Constraints = list.map_corresponding(create_stconstr,
        ArgTVars, FuncArgTypes),
    Constraints = ctconstr([LHS_Constraint | RHS_Constraints],
        tconstr_active, Context, yes(GoalId), no).

%-----------------------------------------------------------------------------%
%
% Constraint generation utility predicates.
%

:- pred pred_has_arity(pred_table::in, int::in, pred_id::in) is semidet.

pred_has_arity(Preds, Arity, PredId) :-
    map.lookup(Preds, PredId, Pred),
    pred_info_get_arg_types(Pred, PredArgTypes),
    list.length(PredArgTypes) = Arity.

    % Converts any builtin atomic type to a string representing that type.
    %
:- pred builtin_atomic_type(cons_id::in, builtin_type::out) is semidet.

builtin_atomic_type(int_const(_), builtin_type_int).
builtin_atomic_type(float_const(_), builtin_type_float).
builtin_atomic_type(string_const(_), builtin_type_string).
builtin_atomic_type(cons(unqualified(String), 0, _), builtin_type_char) :-
    string.char_to_string(_, String).
builtin_atomic_type(impl_defined_const(Name), Type) :-
    (
        ( Name = "file"
        ; Name = "module"
        ; Name = "pred"
        ; Name = "grade"
        ),
        Type = builtin_type_string
    ;
        Name = "line",
        Type = builtin_type_int
    ).

    % Creates a new id for a type constraint, then maps each of the given type
    % variables to that constraint.
    %
:- pred add_type_constraint(list(conj_type_constraint)::in, list(tvar)::in,
    type_constraint_info::in, type_constraint_info::out) is det.

add_type_constraint(Constraints, TVars, !TConstrInfo) :-
    some [!ConstraintCounter, !ConstraintMap, !VarConstraints] (
        !.TConstrInfo = tconstr_info(VarMap, !:ConstraintCounter,
            !:ConstraintMap, !:VarConstraints, TVarSet, Errors),
        (
            Constraints = []
        ;
            (
                Constraints = [SingleConstraint],
                Constraint = tconstr_conj(SingleConstraint)
            ;
                Constraints = [_, _ | _],
                Constraint = tconstr_disj(Constraints, no)
            ),
            counter.allocate(Id, !ConstraintCounter),
            map.det_insert(Id, Constraint, !ConstraintMap),
            list.foldl(map_var_to_constraint(Id), TVars, !VarConstraints)
        ),
        !:TConstrInfo = tconstr_info(VarMap, !.ConstraintCounter,
            !.ConstraintMap, !.VarConstraints, TVarSet, Errors)
    ).

:- pred map_var_to_constraint(type_constraint_id::in, tvar::in,
    var_constraint_map::in, var_constraint_map::out) is det.

map_var_to_constraint(Id, TVar, !VarConstraints) :-
    ( map.search(!.VarConstraints, TVar, OldIds) ->
        ( list.contains(OldIds, Id) ->
            true
        ;
            map.det_update(TVar, [Id | OldIds], !VarConstraints)
        )
    ;
        map.det_insert(TVar, [Id], !VarConstraints)
    ).

    % If a program variable corresponds to a particular type variable, return
    % that type variable. Otherwise, create a new type variable and map the
    % program variable to it, then return that type variable.
    %
:- pred get_var_type(prog_var::in, tvar::out,
    type_constraint_info::in, type_constraint_info::out) is det.

get_var_type(Var, TVar,
        tconstr_info(!.VarMap, CC, CM, VC, !.TVarSet, Errs),
        tconstr_info(!:VarMap, CC, CM, VC, !:TVarSet, Errs)) :-
    ( bimap.search(!.VarMap, Var, TVar0) ->
        TVar = TVar0
    ;
        varset.new_var(TVar, !TVarSet),
        bimap.det_insert(Var, TVar, !VarMap)
    ).

:- func create_stconstr(tvar, mer_type) = simple_type_constraint.

create_stconstr(TVar, Type) = stconstr(TVar, Type).

:- pred get_case_goal(case::in, hlds_goal::out) is det.

get_case_goal(Case, Case ^ case_goal).

:- pred get_ctor_arg_type(constructor_arg::in, mer_type::out) is det.

get_ctor_arg_type(ctor_arg(_, Type, _, _), Type).

:- func tvar_to_type(tvar) = mer_type.

tvar_to_type(TVar) = type_variable(TVar, kind_star).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
%
% Constraint printing.
%

:- pred print_guess(tvarset::in, pair(tvar, type_domain)::in, io::di, io::uo)
    is det.

print_guess(TVarSet, Guess, !IO) :-
    io.print("        Guessing ", !IO),
    print_type_domain(TVarSet, Guess, !IO).

    % If one or more conjunction constraints have become unsatisfiable, print
    % out those constraints
    %
:- pred print_constraint_change(tvarset::in, type_constraint::in,
    type_constraint::in, io::di, io::uo) is det.

print_constraint_change(TVarSet, Constraint0, Constraint1, !IO) :-
    (
        Constraint0 = tconstr_conj(ConjConstraints0),
        Constraint1 = tconstr_conj(ConjConstraints1),
        print_conj_constraint_change(TVarSet,
            ConjConstraints0, ConjConstraints1, !IO)
    ;
        Constraint0 = tconstr_conj(_),
        Constraint1 = tconstr_disj(_, _),
        unexpected($module, $pred, "mismatch")
    ;
        Constraint0 = tconstr_disj(_, _),
        Constraint1 = tconstr_conj(_),
        unexpected($module, $pred, "mismatch")
    ;
        Constraint0 = tconstr_disj(DisjConstraints0, MaybeSingleton0),
        Constraint1 = tconstr_disj(DisjConstraints1, MaybeSingleton1),
        list.foldl_corresponding(print_conj_constraint_change(TVarSet),
            DisjConstraints0, DisjConstraints1, !IO),
        (
            MaybeSingleton0 = no,
            MaybeSingleton1 = yes(_)
        ->
            io.write_string("  Disjunction reduced to one disjunct\n", !IO)
        ;
            true
        )
    ).

:- pred print_conj_constraint_change(tvarset::in, conj_type_constraint::in,
    conj_type_constraint::in, io::di, io::uo) is det.

print_conj_constraint_change(TVarSet, ConjConstraintA, ConjConstraintB, !IO) :-
    ConjConstraintA = ctconstr(_, ActivityA, _, _, _),
    ConjConstraintB = ctconstr(_, ActivityB, _, _, _),
    (
        ActivityA = tconstr_active,
        ActivityB = tconstr_unsatisfiable
    ->
        conj_constraint_to_string(4, TVarSet, ConjConstraintA,
            ConstraintString),
        io.write_string("  Conjunction marked unsatisfiable:\n", !IO),
        io.write_string(ConstraintString ++ "\n", !IO)
    ;
        true
    ).

:- pred print_domain_map_change(tvarset::in, type_domain_map::in,
    pair(tvar, type_domain)::in, io::di, io::uo) is det.

print_domain_map_change(TVarSet, OldDomainMap, TVar - NewDomain, !IO) :-
    ( map.search(OldDomainMap, TVar, OldDomain) ->
        ( equal_domain(OldDomain, NewDomain) ->
            true
        ;
            io.write_string("  Old domain:", !IO),
            print_type_domain(TVarSet, pair(TVar, OldDomain), !IO),
            io.write_string("  New domain:", !IO),
            print_type_domain(TVarSet, pair(TVar, NewDomain), !IO)
        )
    ;
        io.write_string("  New domain added:", !IO),
        print_type_domain(TVarSet, pair(TVar, NewDomain), !IO)
    ).

:- pred print_constraint_solution(type_constraint_info::in,
    prog_varset::in, type_domain_map::in, io::di, io::uo) is det.

print_constraint_solution(TCInfo, ProgVarSet, DomainMap, !IO) :-
    bimap.to_assoc_list(TCInfo ^ tconstr_var_map, VarMapAL),
    list.map(pair.fst, VarMapAL, ProgVars),
    list.map(pair.snd, VarMapAL, RelevantTVars),
    list.map(find_type_domain(DomainMap), RelevantTVars, RelevantDomains),

    io.print("\n", !IO),
    list.foldl_corresponding(print_prog_var_domain(TCInfo ^ tconstr_tvarset,
        ProgVarSet), ProgVars, RelevantDomains, !IO).

:- pred print_prog_var_domain(tvarset::in, prog_varset::in, prog_var::in,
    type_domain::in, io::di, io::uo) is det.

print_prog_var_domain(TVarSet, ProgVarSet, ProgVar, Domain, !IO) :-
    type_domain_to_string(TVarSet, Domain, DomainName),
    VarName = mercury_var_to_string(ProgVarSet, no, ProgVar),
    io.print("  " ++ VarName ++ " -> {" ++ DomainName ++ "}\n", !IO).

:- pred print_type_domain(tvarset::in, pair(tvar, type_domain)::in,
    io::di, io::uo) is det.

print_type_domain(TVarSet, TVar - Domain, !IO) :-
    type_domain_to_string(TVarSet, Domain, DomainName),
    TVarName = mercury_var_to_string(TVarSet, yes, TVar),
    io.print("  " ++ TVarName ++ " -> {" ++ DomainName ++ "}\n", !IO).

:- pred type_domain_to_string(tvarset::in, type_domain::in, string::out)
    is det.

type_domain_to_string(TVarSet, Domain, DomainName) :-
    (
        Domain = tdomain_any,
        DomainName = "any"
    ;
        Domain = tdomain_singleton(Type),
        type_to_string(TVarSet, Type, DomainName)
    ;
        Domain = tdomain(DomainSet),
        list.map(type_to_string(TVarSet), set.to_sorted_list(DomainSet),
            DomainTypeNames),
        DomainName = string.join_list(", ", DomainTypeNames)
    ).

:- pred print_pred_constraint(type_constraint_info::in, prog_varset::in,
    io::di, io::uo) is det.

print_pred_constraint(TCInfo, ProgVarSet, !IO) :-
    TCInfo = tconstr_info(VarMap, _, ConstraintMap, VarConstraints, TVarSet,
        _),
    bimap.to_assoc_list(VarMap, VarMapAssocList),
    list.foldl(print_var_constraints(ConstraintMap, VarConstraints,
        TVarSet, ProgVarSet), VarMapAssocList, !IO).

:- pred print_var_constraints(type_constraint_map::in, var_constraint_map::in,
    tvarset::in, prog_varset::in, pair(prog_var, tvar)::in, io::di, io::uo)
    is det.

print_var_constraints(ConstraintMap, VarConstraints, TVarSet, ProgVarSet,
        Var - TVar, !IO) :-
    VarName = mercury_var_to_string(ProgVarSet, yes, Var),
    TVarName = mercury_var_to_string(TVarSet, yes, TVar),
    io.print(VarName ++ " -> " ++ TVarName ++ "\n", !IO),
    ( map.search(VarConstraints, TVar, ConstraintIds0) ->
        ConstraintIds = ConstraintIds0
    ;
        ConstraintIds = []
    ),
    list.map(constraint_to_string(2, TVarSet, ConstraintMap), ConstraintIds,
        StringReps),
    String = string.join_list(",\n", StringReps),
    io.print(String ++ "\n", !IO).

:- pred constraint_to_string(int::in, tvarset::in, type_constraint_map::in,
    type_constraint_id::in, string::out) is det.

constraint_to_string(Indent, TVarSet, ConstraintMap, ConstraintId, String) :-
    IdString = string.int_to_string(ConstraintId),
    map.lookup(ConstraintMap, ConstraintId, Constraint),
    IndentString = duplicate_char(' ', Indent),
    (
        Constraint = tconstr_conj(ConjConstraints),
        conj_constraint_to_string(Indent, TVarSet, ConjConstraints, ConjString)
    ;
        Constraint = tconstr_disj(Constraints, _),
        list.map(conj_constraint_to_string(Indent+2, TVarSet),
            Constraints, ConjStrings),
        ConjString = IndentString ++ "(\n"
            ++ string.join_list(" OR\n", ConjStrings) ++ "\n"
            ++ IndentString ++ ")"
    ),
    String = IndentString ++ "Constraint " ++ IdString ++ ":\n" ++ ConjString.

:- pred conj_constraint_to_string(int::in, tvarset::in,
    conj_type_constraint::in, string::out) is det.

conj_constraint_to_string(Indent, TVarSet, Constraint, String) :-
    Constraint = ctconstr(SimpleConstraints, _,  Context, _, PredId),
    IndentString = duplicate_char(' ', Indent),
    LineNumber = string.int_to_string(term.context_line(Context)),
    FileName = term.context_file(Context),
    (
        PredId = yes(Id),
        PredString = " (calling predicate " ++
            int_to_string(pred_id_to_int(Id)) ++ ")"
    ;
        PredId = no,
        PredString = ""
    ),
    ContextString = IndentString ++ "[" ++ FileName ++ ": " ++ LineNumber
        ++ PredString ++ "]\n",
    (
        SimpleConstraints = [],
        String0 = "empty conj"
    ;
        SimpleConstraints = [SimpleConstraint],
        simple_constraint_to_string(Indent, TVarSet, SimpleConstraint, String0)
    ;
        SimpleConstraints = [_, _ | _],
        list.map(simple_constraint_to_string(Indent + 2, TVarSet),
            SimpleConstraints, SimpleStrings),
        String0 = IndentString ++ "(\n"
            ++ string.join_list(" AND\n", SimpleStrings) ++ "\n"
            ++ IndentString ++ ")"
    ),
    String = ContextString ++ String0.

:- pred simple_constraint_to_string(int::in, tvarset::in,
    simple_type_constraint::in, string::out) is det.

simple_constraint_to_string(Indent, TVarSet, stconstr(TVar, Type), String) :-
    VarName = mercury_var_to_string(TVarSet, yes, TVar),
    type_to_string(TVarSet, Type, TypeName),
    String = duplicate_char(' ', Indent) ++
        "( " ++ VarName ++ " :: " ++ TypeName ++ ")".

:- pred type_to_string(tvarset::in, mer_type::in, string::out) is det.

type_to_string(TVarSet, Type, Name) :-
    (
        Type = type_variable(TVar,_),
        Name = mercury_var_to_string(TVarSet, yes, TVar)
    ;
        Type = defined_type(SymName, Subtypes, _),
        list.map(type_to_string(TVarSet), Subtypes, SubtypeNames),
        SubtypeName = string.join_list(", ", SubtypeNames),
        Name = sym_name_to_string(SymName) ++ "(" ++ SubtypeName ++ ")"
    ;
        Type = builtin_type(builtin_type_int),
        Name = "int"
    ;
        Type = builtin_type(builtin_type_float),
        Name = "float"
    ;
        Type = builtin_type(builtin_type_string),
        Name = "string"
    ;
        Type = builtin_type(builtin_type_char),
        Name = "character"
    ;
        Type = tuple_type(Subtypes, _),
        list.map(type_to_string(TVarSet), Subtypes, SubtypeNames),
        Name = "{" ++  string.join_list(", ", SubtypeNames) ++ "}"
    ;
        Type = higher_order_type(Subtypes, no, _, _),
        list.map(type_to_string(TVarSet), Subtypes, SubtypeNames),
        Name = "pred(" ++  string.join_list(", ", SubtypeNames) ++ ")"
    ;
        Type = higher_order_type(Subtypes, yes(ReturnType), _, _),
        list.map(type_to_string(TVarSet), Subtypes, SubtypeNames),
        type_to_string(TVarSet, ReturnType, ReturnTypeName),
        Name = "func(" ++  string.join_list(", ", SubtypeNames) ++ ") = "
            ++ ReturnTypeName
    ;
        Type = apply_n_type(_, Subtypes, _),
        list.map(type_to_string(TVarSet), Subtypes, SubtypeNames),
        Name = "func(" ++  string.join_list(", ", SubtypeNames) ++ ")"
    ;
        Type = kinded_type(Type0, _),
        type_to_string(TVarSet, Type0, Name)
    ).

%-----------------------------------------------------------------------------%
%
% General purpose utilities.
%

    % zip_single(Elem, List, NewList):
    %
    % NewList is the result of adding Elem between each element in List.
    % Like string.join_list.
    %
:- pred zip_single(T::in, list(T)::in, list(T)::out) is det.

zip_single(_, [], []).
zip_single(_, [A], [A]).
zip_single(E, [A, A0 | As], [A,E | Bs]) :-
    zip_single(E, [A0 | As], Bs).

%-----------------------------------------------------------------------------%
:- end_module check_hlds.type_constraints.
%-----------------------------------------------------------------------------%
