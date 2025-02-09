%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 1997-2012,2014 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: purity.m
% Main authors: schachte (Peter Schachte, main author and designer of
% purity system), trd (modifications for impure functions).
%
% Purpose: handle `impure' and `promise_pure' declarations; finish off
% type checking.
%
% The main purpose of this module is check the consistency of the `impure' and
% `promise_pure' (etc.) declarations, and to thus report error messages if the
% program is not "purity-correct". This includes treating procedures with
% different clauses for different modes as impure, unless promised pure.
%
% This module also calls post_typecheck.m to perform the final parts of
% type analysis, including
%
% - resolution of predicate and function overloading
% - checking the types of the outer variables in atomic goals, and insertion
%   of their conversions to and from the inner variables.
%
% (See the comments in typecheck.m and post_typecheck.m.)
%
% These actions cannot be done until after type inference is complete,
% so they need to be a separate "post-typecheck pass"; they are done
% here in combination with the purity-analysis pass for efficiency reasons.
%
% We also do elimination of double-negation in this pass.
% It needs to be done somewhere after quantification analysis and
% before mode analysis, and this is a convenient place to do it.
%
% This pass also converts calls to `private_builtin.unsafe_type_cast'
% into `generic_call(unsafe_cast, ...)' goals.
%
%-----------------------------------------------------------------------------%
%
% The aim of Mercury's purity system is to allow one to declare certain parts
% of one's program to be impure, thereby forbidding the compiler from making
% certain optimizations to that part of the code. Since one can often
% implement a perfectly pure predicate or function in terms of impure
% predicates and functions, one is also allowed to promise to the compiler
% that a predicate *is* pure, despite calling impure predicates and
% functions.
%
% To keep purity/impurity consistent, it is required that every impure
% predicate/function be declared so. A predicate is impure if:
%
%   1.  It is declared impure, or
%   2a. It is not promised pure, and
%   2b. It calls some impure predicates or functions.
%
% A predicate or function is declared impure by preceding the `pred' or
% `func' in its declaration with `impure'. It is promised to be pure with a
%
%   :- pragma promise_pure(Name/Arity).
%
% directive.
%
% Calls to impure predicates may not be optimized away. Neither may they be
% reordered relative to any other goals in a given conjunction; i.e., an impure
% goal cleaves a conjunction into the stuff before it and the stuff after it.
% Both of these groups may be reordered separately, but no goal from either
% group may move into the other. Similarly for disjunctions.
%
% Semipure goals are goals that are sensitive to the effects of impure goals.
% They may be reordered and optimized away just like pure goals, except that
% a semipure goal may behave differently after a call to an impure goal than
% before. This means that semipure (as well as impure) predicates must not
% be tabled. Further, duplicate semipure goals on different sides of an
% impure goal must not be optimized away. In the current implementation, we
% simply do not optimize away duplicate semipure (or impure) goals at all.
%
% A predicate either has no purity declaration and so is assumed pure, or is
% declared semipure or impure, or is promised to be pure despite calling
% semipure or impure predicates. This promise cannot be checked, so we must
% trust the programmer.
%
% See the language reference manual for more information on syntax and
% semantics.
%
% The current implementation now handles impure functions.
% They are limited to being used as part of an explicit unification
% with a purity indicator before the goal.
%
%   impure X = some_impure_func(Arg1, Arg2, ...)
%
% This eliminates any need to define some order of evaluation of nested
% impure functions.
%
% Of course it also eliminates the benefits of using functions to cut down
% on the number of variables introduced. The main use of impure functions
% is to interface nicely with foreign language functions.
%
% Any non-variable arguments to the function are flattened into unification
% goals (see unravel_unifications in superhomogeneous.m) which are placed
% as pure goals before the function call itself.
%
% Wishlist:
%   It would be nice to use impure functions in DCG goals as well as
%   normal unifications.
%
%   It might be nice to allow
%       X = impure some_impure_fuc(Arg1, Arg2, ...)
%   syntax aswell. But there are advantages to having the impure or semipure
%   annotation in a regular position (on the left hand side of a goal) too.
%   If this is implemented it should probably be handled in prog_io, and
%   turned into an impure unify item.
%
%   It may also be nice to allow semipure function calls to occur inline
%   (since ordering is not an issue for them).
%
% To do:
%   Reconsider whether impure parallel conjuncts should be allowed.
%
%-----------------------------------------------------------------------------%

:- module check_hlds.purity.
:- interface.

:- import_module hlds.
:- import_module hlds.hlds_module.
:- import_module hlds.hlds_pred.
:- import_module parse_tree.
:- import_module parse_tree.error_util.
:- import_module parse_tree.prog_data.

:- import_module list.

%-----------------------------------------------------------------------------%

    % Purity check a whole module. Also do the post-typecheck stuff described
    % above, and eliminate double negations and calls to
    % `private_builtin.unsafe_type_cast/2'. The first argument specifies
    % whether there were any type errors (if so, we suppress some diagnostics
    % in post_typecheck.m because they are usually spurious). The second
    % argument specifies whether post_typecheck.m detected any errors that
    % would cause problems for later passes (if so, we stop compilation after
    % this pass).
    %
:- pred puritycheck_module(module_info::in, module_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

    % Rerun purity checking on a procedure after an optimization pass has
    % performed transformations which might affect the procedure's purity.
    % repuritycheck_proc makes sure that the goal_infos contain the correct
    % purity, and that the pred_info contains the promised_pure or
    % promised_semipure markers which might be needed if a promised pure
    % procedure was inlined into the procedure being checked.
    %
:- pred repuritycheck_proc(module_info::in, pred_proc_id::in, pred_info::in,
    pred_info::out) is det.

    % Give an error message for unifications marked impure/semipure
    % that are not function calls (e.g. impure X = 4).
    %
:- func impure_unification_expr_error(prog_context, purity) = error_spec.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module check_hlds.post_typecheck.
:- import_module hlds.from_ground_term_util.
:- import_module hlds.goal_util.
:- import_module hlds.hlds_clauses.
:- import_module hlds.hlds_error_util.
:- import_module hlds.hlds_goal.
:- import_module hlds.hlds_rtti.
:- import_module hlds.instmap.
:- import_module hlds.passes_aux.
:- import_module hlds.pred_table.
:- import_module hlds.quantification.
:- import_module mdbcomp.
:- import_module mdbcomp.builtin_modules.
:- import_module mdbcomp.prim_data.
:- import_module mdbcomp.sym_name.
:- import_module parse_tree.builtin_lib_types.
:- import_module parse_tree.mercury_to_mercury.
:- import_module parse_tree.prog_data.
:- import_module parse_tree.prog_mode.
:- import_module parse_tree.prog_out.
:- import_module parse_tree.prog_type.
:- import_module parse_tree.set_of_var.

:- import_module assoc_list.
:- import_module bool.
:- import_module list.
:- import_module map.
:- import_module maybe.
:- import_module pair.
:- import_module require.
:- import_module set.
:- import_module string.
:- import_module term.
:- import_module varset.

%-----------------------------------------------------------------------------%

    % The possible results of a purity check.
:- type purity_check_result
    --->    no_worries
            % All is well.

    ;       insufficient_decl
            % Purity decl is less than required.

    ;       inconsistent_promise
            % Promise is given but decl is impure.

    ;       unnecessary_promise_pure
            % Purity promise is given but not required.

    ;       unnecessary_decl.
            % Purity decl is more than is required.

%-----------------------------------------------------------------------------%

puritycheck_module(!ModuleInfo, !Specs) :-
    module_info_get_valid_predids(PredIds, !ModuleInfo),
    check_preds_purity(PredIds, !ModuleInfo, !Specs).

:- pred check_preds_purity(list(pred_id)::in,
    module_info::in, module_info::out,
    list(error_spec)::in, list(error_spec)::out) is det.

check_preds_purity([], !ModuleInfo, !Specs).
check_preds_purity([PredId | PredIds], !ModuleInfo, !Specs) :-
    module_info_pred_info(!.ModuleInfo, PredId, PredInfo0),
    (
        ( pred_info_is_imported(PredInfo0)
        ; pred_info_is_pseudo_imported(PredInfo0)
        )
    ->
        PredInfo = PredInfo0
    ;
        trace [io(!IO)] (
            write_pred_progress_message("% Purity-checking ", PredId,
                !.ModuleInfo, !IO)
        ),
        puritycheck_pred(PredId, PredInfo0, PredInfo, !.ModuleInfo, !Specs),
        module_info_set_pred_info(PredId, PredInfo, !ModuleInfo)
    ),

    % Finish processing of promise declarations.
    pred_info_get_goal_type(PredInfo, GoalType),
    (
        GoalType = goal_type_promise(PromiseType),
        post_typecheck_finish_promise(PromiseType, PredId, !ModuleInfo, !Specs)
    ;
        ( GoalType = goal_type_clause
        ; GoalType = goal_type_foreign
        ; GoalType = goal_type_clause_and_foreign
        ; GoalType = goal_type_none
        )
    ),
    check_preds_purity(PredIds, !ModuleInfo, !Specs).

%-----------------------------------------------------------------------------%
%
% Check purity of a single predicate.
%
% Purity checking is quite simple. Since impurity /must/ be declared, we can
% perform a single pass checking that the actual purity of each predicate
% matches the declared (or implied) purity. A predicate is just as pure as
% its least pure goal. While we're doing this, we attach a `feature' to each
% goal that is not pure, including non-atomic goals, indicating its purity.
% This information must be maintained by later compilation passes, at least
% until after the last pass that may perform transformations that would not
% be correct for impure code. As we check purity and attach impurity
% features, we also check that impure (semipure) atomic goals were marked in
% the source code as impure (semipure). At this stage in the computation,
% this is indicated by already having the appropriate goal feature. (During
% the translation from term to goal, calls have their purity attached to
% them, and in the translation from goal to hlds_goal, the attached purity is
% turned into the appropriate feature in the hlds_goal_info.)

:- pred puritycheck_pred(pred_id::in, pred_info::in, pred_info::out,
    module_info::in, list(error_spec)::in, list(error_spec)::out) is det.

puritycheck_pred(PredId, !PredInfo, ModuleInfo, !Specs) :-
    pred_info_get_purity(!.PredInfo, DeclPurity),
    pred_info_get_promised_purity(!.PredInfo, PromisedPurity),
    some [!ClausesInfo] (
        pred_info_get_clauses_info(!.PredInfo, !:ClausesInfo),
        clauses_info_clauses(Clauses0, ItemNumbers, !ClausesInfo),
        clauses_info_get_vartypes(!.ClausesInfo, VarTypes0),
        clauses_info_get_varset(!.ClausesInfo, VarSet0),
        PurityInfo0 = purity_info(ModuleInfo, run_post_typecheck,
            !.PredInfo, VarTypes0, VarSet0, [], do_not_need_to_requantify,
            have_not_converted_unify),
        compute_purity_for_clauses(Clauses0, Clauses, !.PredInfo,
            purity_pure, Purity, PurityInfo0, PurityInfo),
        PurityInfo = purity_info(_, _, !:PredInfo,
            VarTypes, VarSet, GoalSpecs, _, _),
        clauses_info_set_vartypes(VarTypes, !ClausesInfo),
        clauses_info_set_varset(VarSet, !ClausesInfo),
        set_clause_list(Clauses, ClausesRep),
        clauses_info_set_clauses_rep(ClausesRep, ItemNumbers, !ClausesInfo),
        pred_info_set_clauses_info(!.ClausesInfo, !PredInfo)
    ),
    WorstPurity = Purity,
    perform_pred_purity_checks(!.PredInfo, Purity, DeclPurity,
        PromisedPurity, PurityCheckResult0),
    % This was to avoid a crash in the following computed goto, when compiled
    % with gcc 4.1 on x86-64. The problem seems to be gone now, but there is
    % not much to gain from removing the workaround.
    PurityCheckResult = workaround_gcc_bug(PurityCheckResult0),
    (
        PurityCheckResult = inconsistent_promise,
        Spec = error_inconsistent_promise(ModuleInfo, !.PredInfo, PredId,
            DeclPurity),
        PredSpecs = [Spec | GoalSpecs]
    ;
        PurityCheckResult = unnecessary_decl,
        Spec = warn_exaggerated_impurity_decl(ModuleInfo, !.PredInfo, PredId,
            DeclPurity, WorstPurity),
        PredSpecs = [Spec | GoalSpecs]
    ;
        PurityCheckResult = insufficient_decl,
        Spec = error_inferred_impure(ModuleInfo, !.PredInfo, PredId, Purity),
        PredSpecs = [Spec | GoalSpecs]
    ;
        PurityCheckResult = unnecessary_promise_pure,
        Spec = warn_unnecessary_promise_pure(ModuleInfo, !.PredInfo, PredId,
            PromisedPurity),
        PredSpecs = [Spec | GoalSpecs]
    ;
        PurityCheckResult = no_worries,
        PredSpecs = GoalSpecs
    ),
    !:Specs = PredSpecs ++ !.Specs.

:- func workaround_gcc_bug(purity_check_result) = purity_check_result.
:- pragma no_inline(workaround_gcc_bug/1).

workaround_gcc_bug(X) = X.

    % Peform purity checking of the actual and declared purity,
    % and check that promises are consistent.
    %
    % ActualPurity:     The inferred purity of the pred.
    % DeclaredPurity:   The declared purity of the pred.
    % Promised:         Did we promise this pred as pure?
    %
:- pred perform_pred_purity_checks(pred_info::in, purity::in, purity::in,
    purity::in, purity_check_result::out) is det.

perform_pred_purity_checks(PredInfo, ActualPurity, DeclaredPurity,
        PromisedPurity, PurityCheckResult) :-
    (
        % The declared purity must match any promises.
        % (A promise of impure means no promise was made).
        PromisedPurity \= purity_impure,
        DeclaredPurity \= PromisedPurity
    ->
        PurityCheckResult = inconsistent_promise
    ;
        % You shouldn't promise pure unnecessarily. It's OK in the case
        % of foreign_procs though. There is also no point in warning about
        % compiler-generated predicates.
        PromisedPurity \= purity_impure,
        ActualPurity = PromisedPurity,
        not pred_info_pragma_goal_type(PredInfo),
        pred_info_get_origin(PredInfo, Origin),
        not (
            Origin = origin_transformed(_, _, _)
        ;
            Origin = origin_created(_)
        )
    ->
        PurityCheckResult = unnecessary_promise_pure
    ;
        % The purity should match the declaration.
        ActualPurity = DeclaredPurity
    ->
        PurityCheckResult = no_worries
    ;
        less_pure(ActualPurity, DeclaredPurity)
    ->
        (
            PromisedPurity = purity_impure,
            PurityCheckResult = insufficient_decl
        ;
            ( PromisedPurity = purity_pure
            ; PromisedPurity = purity_semipure
            ),
            PurityCheckResult = no_worries
        )
    ;
        % We don't warn about exaggerated impurity decls in class methods
        % or instance methods --- it just means that the predicate provided
        % as an implementation was more pure than necessary.
        %
        % We don't warn about exaggerated impurity decls in foreign language
        % code -- this is just because we assume they are pure (XXX we do not
        % do so anymore), but you can declare them to be impure.
        %
        % We don't warn about exaggerated impurity declarations for "stub"
        % procedures, i.e. procedures which originally had no clauses.

        pred_info_get_markers(PredInfo, Markers),
        pred_info_get_goal_type(PredInfo, GoalType),
        ( GoalType = goal_type_foreign
        ; GoalType = goal_type_clause_and_foreign
        ; check_marker(Markers, marker_class_method)
        ; check_marker(Markers, marker_class_instance_method)
        ; check_marker(Markers, marker_stub)
        )
    ->
        PurityCheckResult = no_worries
    ;
        PurityCheckResult = unnecessary_decl
    ).

%-----------------------------------------------------------------------------%

repuritycheck_proc(ModuleInfo, proc(_PredId, ProcId), !PredInfo) :-
    pred_info_get_procedures(!.PredInfo, Procs0),
    map.lookup(Procs0, ProcId, ProcInfo0),
    proc_info_get_goal(ProcInfo0, Goal0),
    proc_info_get_vartypes(ProcInfo0, VarTypes0),
    proc_info_get_varset(ProcInfo0, VarSet0),
    PurityInfo0 = purity_info(ModuleInfo, do_not_run_post_typecheck,
        !.PredInfo, VarTypes0, VarSet0, [], do_not_need_to_requantify,
        have_not_converted_unify),
    compute_goal_purity(Goal0, Goal, Bodypurity, _, PurityInfo0, PurityInfo),
    PurityInfo = purity_info(_, _, !:PredInfo, VarTypes, VarSet, _,
        NeedToRequantify, _),
    proc_info_set_goal(Goal, ProcInfo0, ProcInfo1),
    proc_info_set_vartypes(VarTypes, ProcInfo1, ProcInfo2),
    proc_info_set_varset(VarSet, ProcInfo2, ProcInfo3),
    (
        NeedToRequantify = need_to_requantify,
        requantify_proc_general(ordinary_nonlocals_maybe_lambda,
            ProcInfo3, ProcInfo)
    ;
        NeedToRequantify = do_not_need_to_requantify,
        ProcInfo = ProcInfo3
    ),
    map.det_update(ProcId, ProcInfo, Procs0, Procs),
    pred_info_set_procedures(Procs, !PredInfo),

    % A predicate should never become less pure after inlining, so update
    % any promises in the pred_info if the purity of the goal worsened
    % (for example if a promised pure predicate was inlined).

    pred_info_get_purity(!.PredInfo, OldPurity),
    pred_info_get_markers(!.PredInfo, Markers0),
    (
        less_pure(Bodypurity, OldPurity)
    ->
        (
            OldPurity = purity_pure,
            remove_marker(marker_promised_semipure, Markers0, Markers1),
            add_marker(marker_promised_pure, Markers1, Markers)
        ;
            OldPurity = purity_semipure,
            add_marker(marker_promised_semipure, Markers0, Markers)
        ;
            OldPurity = purity_impure,
            Markers = Markers0
        ),
        pred_info_set_markers(Markers, !PredInfo)
    ;
        less_pure(OldPurity, Bodypurity),
        [_] = pred_info_procids(!.PredInfo)
    ->
        % If there is only one procedure, update the purity in the pred_info
        % if the purity improved.
        %
        % XXX Storing the purity in the pred_info is the wrong thing to do,
        % because optimizations can make some procedures more pure than others.
        (
            Bodypurity = purity_pure,
            remove_marker(marker_is_impure, Markers0, Markers1),
            remove_marker(marker_is_semipure, Markers1, Markers)
        ;
            Bodypurity = purity_semipure,
            remove_marker(marker_is_impure, Markers0, Markers1),
            add_marker(marker_is_semipure, Markers1, Markers)
        ;
            Bodypurity = purity_impure,
            Markers = Markers0
        ),
        pred_info_set_markers(Markers, !PredInfo)
    ;
        true
    ).

%-----------------------------------------------------------------------------%

    % Infer the purity of a single (non-foreign_proc) predicate.
    %
:- pred compute_purity_for_clauses(list(clause)::in, list(clause)::out,
    pred_info::in, purity::in, purity::out,
    purity_info::in, purity_info::out) is det.

compute_purity_for_clauses([], [], _, !Purity, !Info).
compute_purity_for_clauses([Clause0 | Clauses0], [Clause | Clauses], PredInfo,
        !Purity, !Info) :-
    compute_purity_for_clause(Clause0, Clause, PredInfo, ClausePurity, !Info),
    !:Purity = worst_purity(!.Purity, ClausePurity),
    compute_purity_for_clauses(Clauses0, Clauses, PredInfo, !Purity, !Info).

    % Infer the purity of a single clause.
    %
:- pred compute_purity_for_clause(clause::in, clause::out, pred_info::in,
    purity::out, purity_info::in, purity_info::out) is det.

compute_purity_for_clause(Clause0, Clause, PredInfo, Purity, !Info) :-
    Goal0 = Clause0 ^ clause_body,
    Goal0 = hlds_goal(GoalExpr0, GoalInfo0),
    !Info ^ pi_requant := do_not_need_to_requantify,
    compute_expr_purity(GoalExpr0, GoalExpr1, GoalInfo0, BodyPurity0, _,
        !Info),
    % If this clause doesn't apply to all modes of this procedure,
    % i.e. the procedure has different clauses for different modes,
    % then we must treat it as impure, unless the programmer has promised
    % that the clauses are semantically equivalent.
    %
    % The default impurity of foreign_proc procedures is handled when
    % processing the foreign_proc goal -- they are not counted as impure
    % here simply because they have different clauses for different modes.
    (
        (
            ProcIds = pred_info_procids(PredInfo),
            applies_to_all_modes(Clause0, ProcIds)
        ;
            pred_info_get_markers(PredInfo, Markers),
            check_marker(Markers, marker_promised_equivalent_clauses)
        ;
            pred_info_get_goal_type(PredInfo, GoalType),
            GoalType = goal_type_foreign
        )
    ->
        ClausePurity = purity_pure
    ;
        ClausePurity = purity_impure
    ),
    Purity = worst_purity(BodyPurity0, ClausePurity),
    goal_info_set_purity(Purity, GoalInfo0, GoalInfo1),
    Goal1 = hlds_goal(GoalExpr1, GoalInfo1),
    NeedToRequantify = !.Info ^ pi_requant,
    (
        NeedToRequantify = need_to_requantify,
        pred_info_get_clauses_info(PredInfo, ClausesInfo),
        clauses_info_get_headvar_list(ClausesInfo, HeadVars),
        VarTypes1 = !.Info ^ pi_vartypes,
        VarSet1 = !.Info ^ pi_varset,
        % The RTTI varmaps here are just a dummy value, because the real ones
        % are not introduced until polymorphism.
        rtti_varmaps_init(EmptyRttiVarmaps),
        implicitly_quantify_clause_body_general(
            ordinary_nonlocals_maybe_lambda,
            HeadVars, _Warnings, Goal1, Goal,
            VarSet1, VarSet, VarTypes1, VarTypes, EmptyRttiVarmaps, _),
        !Info ^ pi_vartypes := VarTypes,
        !Info ^ pi_varset := VarSet
    ;
        NeedToRequantify = do_not_need_to_requantify,
        Goal = Goal1
    ),
    Clause = Clause0 ^ clause_body := Goal.

:- pred applies_to_all_modes(clause::in, list(proc_id)::in) is semidet.

applies_to_all_modes(Clause, AllProcIds) :-
    ApplicableProcIds = Clause ^ clause_applicable_procs,
    (
        ApplicableProcIds = all_modes
    ;
        ApplicableProcIds = selected_modes(ClauseProcIds),
        % Otherwise the clause applies to the procids in the list.
        % Check if this is the same as the procids for this procedure.
        list.sort(ClauseProcIds, SortedClauseProcIds),
        SortedClauseProcIds = AllProcIds
    ).

%-----------------------------------------------------------------------------%

:- pred compute_goal_purity(hlds_goal::in, hlds_goal::out, purity::out,
    contains_trace_goal::out, purity_info::in, purity_info::out) is det.

compute_goal_purity(Goal0, Goal, Purity, ContainsTrace, !Info) :-
    Goal0 = hlds_goal(GoalExpr0, GoalInfo0),
    compute_expr_purity(GoalExpr0, GoalExpr, GoalInfo0, Purity, ContainsTrace,
        !Info),
    update_purity_ct_in_goal_info(Purity, ContainsTrace, GoalInfo0, GoalInfo),
    Goal = hlds_goal(GoalExpr, GoalInfo).

:- pred update_purity_ct_in_goal_info(purity::in, contains_trace_goal::in,
    hlds_goal_info::in, hlds_goal_info::out) is det.

update_purity_ct_in_goal_info(Purity, ContainsTrace, !GoalInfo) :-
    goal_info_set_purity(Purity, !GoalInfo),
    (
        ContainsTrace = contains_trace_goal,
        goal_info_add_feature(feature_contains_trace, !GoalInfo)
    ;
        ContainsTrace = contains_no_trace_goal,
        goal_info_remove_feature(feature_contains_trace, !GoalInfo)
    ).

    % Compute the purity of a list of hlds_goals. Since the purity of a
    % disjunction is computed the same way as the purity of a conjunction,
    % we use the same code for both
    %
:- pred compute_goals_purity(list(hlds_goal)::in, list(hlds_goal)::out,
    purity::in, purity::out, contains_trace_goal::in, contains_trace_goal::out,
    purity_info::in, purity_info::out) is det.

compute_goals_purity([], [], !Purity, !ContainsTrace, !Info).
compute_goals_purity([Goal0 | Goals0], [Goal | Goals], !Purity, !ContainsTrace,
        !Info) :-
    compute_goal_purity(Goal0, Goal, GoalPurity, GoalContainsTrace, !Info),
    !:Purity = worst_purity(GoalPurity, !.Purity),
    !:ContainsTrace = worst_contains_trace(GoalContainsTrace, !.ContainsTrace),
    compute_goals_purity(Goals0, Goals, !Purity, !ContainsTrace, !Info).

:- pred compute_cases_purity(list(case)::in, list(case)::out,
    purity::in, purity::out, contains_trace_goal::in, contains_trace_goal::out,
    purity_info::in, purity_info::out) is det.

compute_cases_purity([], [], !Purity, !ContainsTrace, !Info).
compute_cases_purity([Case0 | Cases0], [Case | Cases], !Purity, !ContainsTrace,
        !Info) :-
    Case0 = case(MainConsId, OtherConsIds, Goal0),
    compute_goal_purity(Goal0, Goal, GoalPurity, GoalContainsTrace, !Info),
    Case = case(MainConsId, OtherConsIds, Goal),
    !:Purity = worst_purity(GoalPurity, !.Purity),
    !:ContainsTrace = worst_contains_trace(GoalContainsTrace, !.ContainsTrace),
    compute_cases_purity(Cases0, Cases, !Purity, !ContainsTrace, !Info).

:- pred compute_parallel_goals_purity(list(hlds_goal)::in,
    list(hlds_goal)::out, purity::in, purity::out, contains_trace_goal::in,
    contains_trace_goal::out, purity_info::in, purity_info::out) is det.

compute_parallel_goals_purity([], [], !Purity, !ContainsTrace, !Info).
compute_parallel_goals_purity([Goal0 | Goals0], [Goal | Goals], !Purity,
        !ContainsTrace, !Info) :-
    compute_goal_purity(Goal0, Goal, GoalPurity, GoalContainsTrace, !Info),
    (
        ( GoalPurity = purity_pure
        ; GoalPurity = purity_semipure
        )
    ;
        GoalPurity = purity_impure,
        Goal0 = hlds_goal(_, GoalInfo0),
        Context = goal_info_get_context(GoalInfo0),
        Spec = impure_parallel_conjunct_error(Context, GoalPurity),
        purity_info_add_message(Spec, !Info)
    ),
    !:Purity = worst_purity(GoalPurity, !.Purity),
    !:ContainsTrace = worst_contains_trace(GoalContainsTrace, !.ContainsTrace),
    compute_parallel_goals_purity(Goals0, Goals, !Purity, !ContainsTrace,
        !Info).

%-----------------------------------------------------------------------------%

:- pred compute_expr_purity(hlds_goal_expr::in, hlds_goal_expr::out,
    hlds_goal_info::in, purity::out, contains_trace_goal::out,
    purity_info::in, purity_info::out) is det.

compute_expr_purity(GoalExpr0, GoalExpr, GoalInfo, Purity, ContainsTrace,
        !Info) :-
    (
        GoalExpr0 = conj(ConjType, Goals0),
        (
            ConjType = plain_conj,
            compute_goals_purity(Goals0, Goals, purity_pure, Purity,
                contains_no_trace_goal, ContainsTrace, !Info)
        ;
            ConjType = parallel_conj,
            compute_parallel_goals_purity(Goals0, Goals, purity_pure, Purity,
                contains_no_trace_goal, ContainsTrace, !Info)
        ),
        GoalExpr = conj(ConjType, Goals)
    ;
        GoalExpr0 = plain_call(PredId0, ProcId, ArgVars, Status,
            MaybeUnifyContext, SymName0),
        RunPostTypecheck = !.Info ^ pi_run_post_typecheck,
        PredInfo = !.Info ^ pi_pred_info,
        ModuleInfo = !.Info ^ pi_module_info,
        CallContext = goal_info_get_context(GoalInfo),
        (
            RunPostTypecheck = run_post_typecheck,
            finally_resolve_pred_overloading(ArgVars, PredInfo, ModuleInfo,
                CallContext, SymName0, SymName, PredId0, PredId),
            (
                % Convert any calls to private_builtin.unsafe_type_cast
                % into unsafe_type_cast generic calls.
                SymName = qualified(mercury_private_builtin_module,
                    "unsafe_type_cast"),
                ArgVars = [InputArg, OutputArg]
            ->
                GoalExpr = generic_call(cast(unsafe_type_cast),
                    [InputArg, OutputArg], [in_mode, out_mode],
                    arg_reg_types_unset, detism_det)
            ;
                GoalExpr = plain_call(PredId, ProcId, ArgVars, Status,
                    MaybeUnifyContext, SymName)
            )
        ;
            RunPostTypecheck = do_not_run_post_typecheck,
            PredId = PredId0,
            GoalExpr = GoalExpr0
        ),
        DeclaredPurity = goal_info_get_purity(GoalInfo),
        perform_goal_purity_checks(CallContext, PredId,
            DeclaredPurity, ActualPurity, !Info),
        Purity = ActualPurity,
        ContainsTrace = contains_no_trace_goal
    ;
        GoalExpr0 = generic_call(GenericCall0, _ArgVars, _Modes0,
            _MaybeArgRegs, _Det),
        GoalExpr = GoalExpr0,
        (
            GenericCall0 = higher_order(_, Purity, _, _)
        ;
            GenericCall0 = class_method(_, _, _, _),
            Purity = purity_pure                        % XXX this is wrong!
        ;
            ( GenericCall0 = cast(_)
            ; GenericCall0 = event_call(_)
            ),
            Purity = purity_pure
        ),
        ContainsTrace = contains_no_trace_goal
    ;
        GoalExpr0 = switch(Var, Canfail, Cases0),
        compute_cases_purity(Cases0, Cases, purity_pure, Purity,
            contains_no_trace_goal, ContainsTrace, !Info),
        GoalExpr = switch(Var, Canfail, Cases)
    ;
        GoalExpr0 = unify(LHSVar, RHS0, Mode, Unification, UnifyContext),
        (
            RHS0 = rhs_lambda_goal(LambdaPurity, Groundness, PredOrFunc,
                EvalMethod, LambdaNonLocals, LambdaQuantVars,
                LambdaModes, LambdaDetism, LambdaGoal0),
            LambdaGoal0 = hlds_goal(LambdaGoalExpr0, LambdaGoalInfo0),
            compute_expr_purity(LambdaGoalExpr0, LambdaGoalExpr,
                LambdaGoalInfo0, GoalPurity, _, !Info),
            LambdaGoal = hlds_goal(LambdaGoalExpr, LambdaGoalInfo0),
            RHS = rhs_lambda_goal(LambdaPurity, Groundness, PredOrFunc,
                EvalMethod, LambdaNonLocals, LambdaQuantVars,
                LambdaModes, LambdaDetism, LambdaGoal),

            check_closure_purity(GoalInfo, LambdaPurity, GoalPurity,
                ClosureSpecs),
            purity_info_add_messages(ClosureSpecs, !Info),
            GoalExpr = unify(LHSVar, RHS, Mode, Unification, UnifyContext),
            % The unification itself is always pure,
            % even if the lambda expression body is impure.
            DeclaredPurity = goal_info_get_purity(GoalInfo),
            (
                ( DeclaredPurity = purity_impure
                ; DeclaredPurity = purity_semipure
                ),
                Context = goal_info_get_context(GoalInfo),
                Spec = impure_unification_expr_error(Context, DeclaredPurity),
                purity_info_add_message(Spec, !Info)
            ;
                DeclaredPurity = purity_pure
            ),
            ActualPurity = purity_pure,
            ContainsTrace = contains_no_trace_goal
        ;
            RHS0 = rhs_functor(ConsId, _, Args),
            RunPostTypecheck = !.Info ^ pi_run_post_typecheck,
            (
                RunPostTypecheck = run_post_typecheck,
                ModuleInfo = !.Info ^ pi_module_info,
                PredInfo0 = !.Info ^ pi_pred_info,
                VarTypes0 = !.Info ^ pi_vartypes,
                VarSet0 = !.Info ^ pi_varset,
                post_typecheck.resolve_unify_functor(LHSVar, ConsId, Args,
                    Mode, Unification, UnifyContext, GoalInfo, ModuleInfo,
                    PredInfo0, PredInfo, VarSet0, VarSet, VarTypes0, VarTypes,
                    Goal1, IsPlainUnify),
                !Info ^ pi_vartypes := VarTypes,
                !Info ^ pi_varset := VarSet,
                !Info ^ pi_pred_info := PredInfo,
                (
                    IsPlainUnify = is_plain_unify
                ;
                    IsPlainUnify = is_not_plain_unify,
                    !Info ^ pi_converted_unify := have_converted_unify
                ;
                    IsPlainUnify = is_unknown_ref(Spec),
                    purity_info_add_message(Spec, !Info)
                )
            ;
                RunPostTypecheck = do_not_run_post_typecheck,
                Goal1 = hlds_goal(GoalExpr0, GoalInfo)
            ),
            ( Goal1 = hlds_goal(unify(_, _, _, _, _), _) ->
                check_var_functor_unify_purity(!.Info, GoalInfo,
                    LHSVar, ConsId, Args, UnifySpecs),
                purity_info_add_messages(UnifySpecs, !Info),
                ActualPurity = purity_pure,
                ContainsTrace = contains_no_trace_goal,
                Goal = Goal1
            ;
                compute_goal_purity(Goal1, Goal, ActualPurity, ContainsTrace,
                    !Info)
            ),
            Goal = hlds_goal(GoalExpr, _)
        ;
            RHS0 = rhs_var(_),
            GoalExpr = GoalExpr0,
            ActualPurity = purity_pure,
            ContainsTrace = contains_no_trace_goal
        ),
        Purity = ActualPurity
    ;
        GoalExpr0 = disj(Goals0),
        compute_goals_purity(Goals0, Goals, purity_pure, Purity,
            contains_no_trace_goal, ContainsTrace, !Info),
        GoalExpr = disj(Goals)
    ;
        GoalExpr0 = negation(Goal0),
        % Eliminate double negation.
        negate_goal(Goal0, GoalInfo, NotGoal0),
        ( NotGoal0 = hlds_goal(negation(Goal1), _) ->
            compute_goal_purity(Goal1, Goal, Purity, ContainsTrace, !Info),
            GoalExpr = negation(Goal)
        ;
            compute_goal_purity(NotGoal0, NotGoal1, Purity, ContainsTrace,
                !Info),
            NotGoal1 = hlds_goal(GoalExpr, _)
        )
    ;
        GoalExpr0 = scope(Reason0, SubGoal0),
        (
            Reason0 = promise_purity(PromisedPurity),
            compute_goal_purity(SubGoal0, SubGoal, _, ContainsTrace, !Info),
            GoalExpr = scope(Reason0, SubGoal),
            Purity = PromisedPurity
        ;
            Reason0 = from_ground_term(TermVar, Kind0),
            (
                ( Kind0 = from_ground_term_initial
                ; Kind0 = from_ground_term_construct
                ),
                SubGoal0 = hlds_goal(SubGoalExpr0, SubGoalInfo0),
                ( SubGoalExpr0 = conj(plain_conj, SubGoals0Prime) ->
                    SubGoals0 = SubGoals0Prime
                ;
                    unexpected($module, $pred,
                        "from_ground_term_initial goal is not plain conj")
                ),
                PostTypeCheck = !.Info ^ pi_run_post_typecheck,
                (
                    PostTypeCheck = run_post_typecheck,
                    compute_goal_purity_in_fgt_ptc(SubGoals0,
                        [], RevMarkedSubGoals, purity_pure, Purity,
                        contains_no_trace_goal, ContainsTrace, !Info,
                        fgt_invariants_kept, Invariants),
                    (
                        Invariants = fgt_invariants_kept,
                        list.map(project_kept_goal,
                            RevMarkedSubGoals, RevSubGoals),
                        list.reverse(RevSubGoals, SubGoals),
                        SubGoalExpr = conj(plain_conj, SubGoals),
                        update_purity_ct_in_goal_info(Purity, ContainsTrace,
                            SubGoalInfo0, SubGoalInfo),
                        SubGoal = hlds_goal(SubGoalExpr, SubGoalInfo),
                        GoalExpr = scope(Reason0, SubGoal)
                    ;
                        Invariants = fgt_invariants_broken,
                        (
                            Kind0 = from_ground_term_initial,
                            ConstructOrderMarkedSubGoals = RevMarkedSubGoals,
                            Order = deconstruct_top_down
                        ;
                            Kind0 = from_ground_term_construct,
                            list.reverse(RevMarkedSubGoals,
                                ConstructOrderMarkedSubGoals),
                            Order = construct_bottom_up
                        ),
                        introduce_partial_fgt_scopes(GoalInfo, SubGoalInfo0,
                            ConstructOrderMarkedSubGoals, Order, SubGoal),
                        % Delete the scope wrapper around SubGoal0.
                        SubGoal = hlds_goal(GoalExpr, _)
                    )
                ;
                    PostTypeCheck = do_not_run_post_typecheck,
                    GoalExpr = GoalExpr0,
                    compute_goal_purity_in_fgt_no_ptc(SubGoals0, !.Info,
                        [], Specs),
                    purity_info_add_messages(Specs, !Info),
                    Purity = purity_pure,
                    ContainsTrace = contains_no_trace_goal
                )
            ;
                ( Kind0 = from_ground_term_deconstruct
                ; Kind0 = from_ground_term_other
                ),
                !Info ^ pi_converted_unify := have_not_converted_unify,
                compute_goal_purity(SubGoal0, SubGoal, Purity, ContainsTrace,
                    !Info),
                HaveConvertedUnify = !.Info ^ pi_converted_unify,
                (
                    HaveConvertedUnify = have_not_converted_unify,
                    GoalExpr = scope(Reason0, SubGoal)
                ;
                    HaveConvertedUnify = have_converted_unify,
                    % We could delete the scope. However, there may be
                    % some compiler passes than could benefit from it,
                    % and I expect we will get here rarely enough that
                    % what we do here does not matter all that much.
                    Reason = from_ground_term(TermVar, from_ground_term_other),
                    GoalExpr = scope(Reason, SubGoal)
                )
            )
        ;
            ( Reason0 = promise_solutions(_, _)
            ; Reason0 = require_detism(_)
            ; Reason0 = require_complete_switch(_)
            ; Reason0 = commit(_)
            ; Reason0 = barrier(_)
            ; Reason0 = exist_quant(_)
            ),
            compute_goal_purity(SubGoal0, SubGoal, Purity, ContainsTrace,
                !Info),
            GoalExpr = scope(Reason0, SubGoal)
        ;
            Reason0 = trace_goal(_, _, _, _, _),
            compute_goal_purity(SubGoal0, SubGoal, _SubPurity, _, !Info),
            GoalExpr = scope(Reason0, SubGoal),
            Purity = purity_pure,
            ContainsTrace = contains_trace_goal
        ;
            % Purity checking happens before the introduction of loop control
            % scopes.
            Reason0 = loop_control(_, _, _),
            unexpected($module, $pred, "loop_control")
        )
    ;
        GoalExpr0 = if_then_else(Vars, Cond0, Then0, Else0),
        compute_goal_purity(Cond0, Cond, Purity1, ContainsTrace1, !Info),
        compute_goal_purity(Then0, Then, Purity2, ContainsTrace2, !Info),
        compute_goal_purity(Else0, Else, Purity3, ContainsTrace3, !Info),
        worst_purity(Purity1, Purity2) = Purity12,
        worst_purity(Purity12, Purity3) = Purity,
        (
            ( ContainsTrace1 = contains_trace_goal
            ; ContainsTrace2 = contains_trace_goal
            ; ContainsTrace3 = contains_trace_goal
            )
        ->
            ContainsTrace = contains_trace_goal
        ;
            ContainsTrace = contains_no_trace_goal
        ),
        GoalExpr = if_then_else(Vars, Cond, Then, Else)
    ;
        GoalExpr0 = call_foreign_proc(Attributes, _, _, _, _, _, _),
        Purity = get_purity(Attributes),
        ContainsTrace = contains_no_trace_goal,
        GoalExpr = GoalExpr0
    ;
        GoalExpr0 = shorthand(ShortHand0),
        (
            ShortHand0 = atomic_goal(GoalType, Outer, Inner, MaybeOutputVars,
                MainGoal0, OrElseGoals0, OrElseInners),
            RunPostTypecheck = !.Info ^ pi_run_post_typecheck,
            (
                RunPostTypecheck = run_post_typecheck,
                VarSet = !.Info ^ pi_varset,
                VarTypes = !.Info ^ pi_vartypes,
                Outer = atomic_interface_vars(OuterDI, OuterUO),
                Context = goal_info_get_context(GoalInfo),
                check_outer_var_type(Context, VarTypes, VarSet, OuterDI,
                    _OuterDIType, OuterDITypeSpecs),
                check_outer_var_type(Context, VarTypes, VarSet, OuterUO,
                    _OuterUOType, OuterUOTypeSpecs),
                OuterTypeSpecs = OuterDITypeSpecs ++ OuterUOTypeSpecs,
                (
                    OuterTypeSpecs = [_ | _],
                    list.foldl(purity_info_add_message, OuterTypeSpecs, !Info),
                    MainGoal1 = MainGoal0,
                    OrElseGoals1 = OrElseGoals0
                ;
                    OuterTypeSpecs = [],
                    AtomicGoalsAndInners = assoc_list.from_corresponding_lists(
                        [MainGoal0 | OrElseGoals0],
                        [Inner | OrElseInners]),
                    list.map_foldl(wrap_inner_outer_goals(Outer),
                        AtomicGoalsAndInners, AllAtomicGoals1, !Info),
                    (
                        AllAtomicGoals1 = [MainGoal1 | OrElseGoals1]
                    ;
                        AllAtomicGoals1 = [],
                        unexpected($module, $pred, "AllAtomicGoals1 = []")
                    ),
                    !Info ^ pi_requant := need_to_requantify
                )
            ;
                RunPostTypecheck = do_not_run_post_typecheck,
                MainGoal1 = MainGoal0,
                OrElseGoals1 = OrElseGoals0
            ),
            compute_goal_purity(MainGoal1, MainGoal, Purity1, ContainsTrace1,
                !Info),
            compute_goals_purity(OrElseGoals1, OrElseGoals,
                purity_pure, Purity2, contains_no_trace_goal, ContainsTrace2,
                !Info),
            Purity = worst_purity(Purity1, Purity2),
            (
                ( ContainsTrace1 = contains_trace_goal
                ; ContainsTrace2 = contains_trace_goal
                )
            ->
                ContainsTrace = contains_trace_goal
            ;
                ContainsTrace = contains_no_trace_goal
            ),
            ShortHand = atomic_goal(GoalType, Outer, Inner, MaybeOutputVars,
                MainGoal, OrElseGoals, OrElseInners),
            GoalExpr = shorthand(ShortHand)
        ;
            ShortHand0 = try_goal(MaybeIO, ResultVar, SubGoal0),
            compute_goal_purity(SubGoal0, SubGoal, Purity, ContainsTrace,
                !Info),
            ShortHand = try_goal(MaybeIO, ResultVar, SubGoal),
            GoalExpr = shorthand(ShortHand)
        ;
            ShortHand0 = bi_implication(_, _),
            % These should have been expanded out by now.
            unexpected($module, $pred, "bi_implication")
        )
    ).

%-----------------------------------------------------------------------------%
%
% Auxiliary procedures for handling from_ground_term scopes.
%

:- pred compute_goal_purity_in_fgt_ptc(list(hlds_goal)::in,
    list(fgt_marked_goal)::in, list(fgt_marked_goal)::out,
    purity::in, purity::out, contains_trace_goal::in, contains_trace_goal::out,
    purity_info::in, purity_info::out,
    fgt_invariants_status::in, fgt_invariants_status::out) is det.

compute_goal_purity_in_fgt_ptc([], !RevMarkedSubGoals,
        !Purity, !ContainsTrace, !Info, !Invariants).
compute_goal_purity_in_fgt_ptc([Goal0 | Goals0], !RevMarkedSubGoals,
        !Purity, !ContainsTrace, !Info, !Invariants) :-
    Goal0 = hlds_goal(GoalExpr0, GoalInfo0),
    (
        GoalExpr0 = unify(XVarPrime, Y, ModePrime, UnificationPrime,
            UnifyContextPrime),
        Y = rhs_functor(ConsIdPrime, _, YVarsPrime)
    ->
        XVar = XVarPrime,
        Mode = ModePrime,
        Unification = UnificationPrime,
        UnifyContext = UnifyContextPrime,
        ConsId = ConsIdPrime,
        YVars = YVarsPrime
    ;
        unexpected($module, $pred,
            "from_ground_term_initial conjunct is not functor unify")
    ),
    ModuleInfo = !.Info ^ pi_module_info,
    PredInfo0 = !.Info ^ pi_pred_info,
    VarTypes0 = !.Info ^ pi_vartypes,
    VarSet0 = !.Info ^ pi_varset,
    post_typecheck.resolve_unify_functor(XVar, ConsId, YVars, Mode,
        Unification, UnifyContext, GoalInfo0, ModuleInfo,
        PredInfo0, PredInfo, VarSet0, VarSet, VarTypes0, VarTypes,
        Goal1, IsPlainUnify),
    Goal1 = hlds_goal(GoalExpr1, GoalInfo1),
    (
        IsPlainUnify = is_plain_unify,
        trace [compiletime(flag("purity_fgt_sanity_tests"))] (
            ( GoalExpr1 = unify(_, _, _, _, _) ->
                true
            ;
                unexpected($module, $pred, "is_plain_unify goal is not unify")
            ),
            expect(unify(PredInfo0, PredInfo),
                $module, $pred, "PredInfo != PredInfo"),
            expect(unify(VarSet0, VarSet),
                $module, $pred, "VarSet != VarSet"),
            expect(unify(VarTypes0, VarTypes),
                $module, $pred, "VarTypes != VarTypes")
        ),
        check_var_functor_unify_purity(!.Info, GoalInfo0, XVar, ConsId, YVars,
            UnifySpecs),
        purity_info_add_messages(UnifySpecs, !Info),
        % !Purity and !ContainsTrace are unchanged.
        update_purity_ct_in_goal_info(purity_pure, contains_no_trace_goal,
            GoalInfo1, GoalInfo),
        Goal = hlds_goal(GoalExpr1, GoalInfo),
        % Goal may be different from Goal0 (e.g. it may have the cons_id
        % module qualified), but if resolve_unify_functor returned
        % is_plain_unify, then the change does not invalidate
        % the invariants of from_ground_term_{initial,construct} scopes.
        MarkedSubGoal = fgt_kept_goal(Goal, XVar, YVars)
        % !Invariants is unchanged.
    ;
        IsPlainUnify = is_not_plain_unify,
        !Info ^ pi_vartypes := VarTypes,
        !Info ^ pi_varset := VarSet,
        !Info ^ pi_pred_info := PredInfo,
        ( GoalExpr1 = unify(_, _, _, _, _) ->
            check_var_functor_unify_purity(!.Info, GoalInfo0,
                XVar, ConsId, YVars, UnifySpecs),
            purity_info_add_messages(UnifySpecs, !Info),
            update_purity_ct_in_goal_info(purity_pure, contains_no_trace_goal,
                GoalInfo1, GoalInfo),
            Goal = hlds_goal(GoalExpr1, GoalInfo)
            % !Purity and !ContainsTrace are unchanged.
        ;
            compute_goal_purity(Goal1, Goal, GoalPurity, GoalContainsTrace,
                !Info),
            !:Purity = worst_purity(GoalPurity, !.Purity),
            !:ContainsTrace = worst_contains_trace(GoalContainsTrace,
                !.ContainsTrace)
        ),
        MarkedSubGoal = fgt_broken_goal(Goal, XVar, YVars),
        !:Invariants = fgt_invariants_broken
    ;
        IsPlainUnify = is_unknown_ref(Spec),
        purity_info_add_message(Spec, !Info),
        MarkedSubGoal = fgt_broken_goal(Goal1, XVar, YVars),
        !:Invariants = fgt_invariants_broken
    ),
    !:RevMarkedSubGoals = [MarkedSubGoal | !.RevMarkedSubGoals],
    compute_goal_purity_in_fgt_ptc(Goals0, !RevMarkedSubGoals,
        !Purity, !ContainsTrace, !Info, !Invariants).

:- pred compute_goal_purity_in_fgt_no_ptc(list(hlds_goal)::in,
    purity_info::in, list(error_spec)::in, list(error_spec)::out) is det.

compute_goal_purity_in_fgt_no_ptc([], _, !Specs).
compute_goal_purity_in_fgt_no_ptc([Goal0 | Goals0], Info, !Specs) :-
    Goal0 = hlds_goal(GoalExpr0, GoalInfo0),
    (
        GoalExpr0 = unify(XVarPrime, Y, _, _, _),
        Y = rhs_functor(ConsIdPrime, _, YVarsPrime)
    ->
        XVar = XVarPrime,
        ConsId = ConsIdPrime,
        YVars = YVarsPrime
    ;
        unexpected($module, $pred,
            "from_ground_term_initial conjunct is not functor unify")
    ),
    check_var_functor_unify_purity(Info, GoalInfo0, XVar, ConsId, YVars,
        UnifySpecs),
    !:Specs = UnifySpecs ++ !.Specs,
    compute_goal_purity_in_fgt_no_ptc(Goals0, Info, !Specs).

%-----------------------------------------------------------------------------%
%
% Auxiliary procedures for handling plain calls.
%

    % Perform purity checking of the actual and declared purity,
    % and check that promises are consistent.
    %
    % ActualPurity: The inferred purity of the goal
    % DeclaredPurity: The declared purity of the goal
    %
:- pred perform_goal_purity_checks(prog_context::in, pred_id::in, purity::in,
    purity::out, purity_info::in, purity_info::out) is det.

perform_goal_purity_checks(Context, PredId, DeclaredPurity, ActualPurity,
        !Info) :-
    ModuleInfo = !.Info ^ pi_module_info,
    PredInfo = !.Info ^ pi_pred_info,
    module_info_pred_info(ModuleInfo, PredId, CalleePredInfo),
    pred_info_get_purity(CalleePredInfo, ActualPurity),
    (
        % The purity of the callee should match the
        % purity declared at the call.
        ActualPurity = DeclaredPurity
    ->
        true
    ;
        % Don't require purity annotations on calls in
        % compiler-generated code.
        is_unify_or_compare_pred(PredInfo)
    ->
        true
    ;
        less_pure(ActualPurity, DeclaredPurity)
    ->
        Spec = error_missing_body_impurity_decl(ModuleInfo, PredId,
            Context),
        purity_info_add_message(Spec, !Info)
    ;
        % We don't warn about exaggerated impurity decls in class methods
        % or instance methods --- it just means that the predicate provided
        % as an implementation was more pure than necessary.
        % Don't warn about exaggerated impurity decls in compiler-generated
        % mutable predicates either.

        pred_info_get_markers(PredInfo, Markers),
        ( check_marker(Markers, marker_class_method)
        ; check_marker(Markers, marker_class_instance_method)
        ; check_marker(Markers, marker_mutable_access_pred)
        )
    ->
        true
    ;
        Spec = warn_unnecessary_body_impurity_decl(ModuleInfo, PredId,
            Context, DeclaredPurity),
        purity_info_add_message(Spec, !Info)
    ).

%-----------------------------------------------------------------------------%
%
% Auxiliary procedures for handling unifications.
%

:- pred check_var_functor_unify_purity(purity_info::in, hlds_goal_info::in,
    prog_var::in, cons_id::in, list(prog_var)::in, list(error_spec)::out)
    is det.

check_var_functor_unify_purity(Info, GoalInfo, Var, ConsId, Args, Specs) :-
    % If the unification involves a higher order RHS, check that
    % the purity of the ConsId matches the purity of the variable's type.
    VarTypes = Info ^ pi_vartypes,
    lookup_var_type(VarTypes, Var, TypeOfVar),
    PredInfo = Info ^ pi_pred_info,
    pred_info_get_markers(PredInfo, CallerMarkers),
    Context = goal_info_get_context(GoalInfo),
    (
        ConsId = cons(PName, _, _),
        type_is_higher_order_details(TypeOfVar, TypePurity, PredOrFunc,
            _EvalMethod, VarArgTypes)
    ->
        pred_info_get_typevarset(PredInfo, TVarSet),
        pred_info_get_exist_quant_tvars(PredInfo, ExistQTVars),
        pred_info_get_head_type_params(PredInfo, HeadTypeParams),
        lookup_var_types(VarTypes, Args, ArgTypes0),
        list.append(ArgTypes0, VarArgTypes, PredArgTypes),
        ModuleInfo = Info ^ pi_module_info,
        (
            get_pred_id_by_types(calls_are_fully_qualified(CallerMarkers),
                PName, PredOrFunc, TVarSet, ExistQTVars, PredArgTypes,
                HeadTypeParams, ModuleInfo, Context, CalleePredId)
        ->
            module_info_pred_info(ModuleInfo, CalleePredId, CalleePredInfo),
            pred_info_get_purity(CalleePredInfo, CalleePurity),
            check_closure_purity(GoalInfo, TypePurity, CalleePurity,
                ClosureSpecs)
        ;
            % If we can't find the type of the function, it is because
            % typecheck couldn't give it one. Typechecking gives an error
            % in this case, we just keep silent.
            ClosureSpecs = []
        )
    ;
        % No closure; no specs.
        ClosureSpecs = []
    ),

    % The unification itself is always pure,
    % even if it is a unification with an impure higher-order term.
    % Check for a bogus purity annotation on the unification.
    DeclaredPurity = goal_info_get_purity(GoalInfo),
    (
        ( DeclaredPurity = purity_semipure
        ; DeclaredPurity = purity_impure
        ),
        % Don't warn about bogus purity annotations in compiler-generated
        % mutable predicates.
        ( check_marker(CallerMarkers, marker_mutable_access_pred) ->
            Specs = ClosureSpecs
        ;
            Spec = impure_unification_expr_error(Context, DeclaredPurity),
            Specs = [Spec | ClosureSpecs]
        )
    ;
        DeclaredPurity = purity_pure,
        Specs = ClosureSpecs
    ).

:- pred check_closure_purity(hlds_goal_info::in, purity::in, purity::in,
    list(error_spec)::out) is det.

check_closure_purity(GoalInfo, DeclaredPurity, ActualPurity, Specs) :-
    ( less_pure(ActualPurity, DeclaredPurity) ->
        Context = goal_info_get_context(GoalInfo),
        Spec = report_error_closure_purity(Context,
            DeclaredPurity, ActualPurity),
        Specs = [Spec]
    ;
        % We don't bother to warn if the DeclaredPurity is less pure than the
        % ActualPurity; that would lead to too many spurious warnings.
        Specs = []
    ).

%-----------------------------------------------------------------------------%
%
% Auxiliary procedures for handling atomic goals.
%

:- pred check_outer_var_type(prog_context::in, vartypes::in, prog_varset::in,
    prog_var::in, mer_type::out, list(error_spec)::out) is det.

check_outer_var_type(Context, VarTypes, VarSet, Var, VarType, Specs) :-
    lookup_var_type(VarTypes, Var, VarType),
    (
        ( VarType = io_state_type
        ; VarType = stm_atomic_type
        )
    ->
        Specs = []
    ;
        Spec = bad_outer_var_type_error(Context, VarSet, Var),
        Specs = [Spec]
    ).

:- pred wrap_inner_outer_goals(atomic_interface_vars::in,
    pair(hlds_goal, atomic_interface_vars)::in, hlds_goal::out,
    purity_info::in, purity_info::out) is det.

wrap_inner_outer_goals(Outer, Goal0 - Inner, Goal, !Info) :-
    Goal0 = hlds_goal(_, GoalInfo0),
    NonLocals0 = goal_info_get_nonlocals(GoalInfo0),
    Context = goal_info_get_context(GoalInfo0),
    Outer = atomic_interface_vars(OuterDI, OuterUO),
    Inner = atomic_interface_vars(InnerDI, InnerUO),

    % Generate the STM outer_to_inner and inner_to_outer goals.
    OuterToInnerPred = "stm_from_outer_to_inner",
    InnerToOuterPred = "stm_from_inner_to_outer",
    ModuleInfo = !.Info ^ pi_module_info,
    generate_simple_call(mercury_stm_builtin_module,
        OuterToInnerPred, pf_predicate, only_mode,
        detism_det, purity_pure, [OuterDI, InnerDI], [],
        instmap_delta_from_assoc_list([OuterDI - ground(clobbered, none),
            InnerDI - ground(unique, none)]),
        ModuleInfo, Context, OuterToInnerGoal),
    generate_simple_call(mercury_stm_builtin_module,
        InnerToOuterPred, pf_predicate, only_mode,
        detism_det, purity_pure, [InnerUO, OuterUO], [],
        instmap_delta_from_assoc_list([InnerUO - ground(clobbered, none),
            OuterUO - ground(unique, none)]),
        ModuleInfo, Context, InnerToOuterGoal),

    WrapExpr = conj(plain_conj, [OuterToInnerGoal, Goal0, InnerToOuterGoal]),
    % After the addition of OuterToInnerGoal and InnerToOuterGoal,
    % OuterDI and OuterUO will definitely be used by the code inside the new
    % goal, and *should* be used by code outside the goal. However, even if
    % they are not, the nonlocals set is allowed to overapproximate.
    set_of_var.insert_list([OuterDI, OuterUO], NonLocals0, NonLocals),
    goal_info_set_nonlocals(NonLocals, GoalInfo0, GoalInfo1),
    goal_info_add_feature(feature_contains_stm_inner_outer, GoalInfo1,
        GoalInfo),
    Goal = hlds_goal(WrapExpr, GoalInfo).

%-----------------------------------------------------------------------------%
%
% This part of the module is for generating error messages.
%

:- func pred_context(module_info, pred_info, pred_id) = list(format_component).

pred_context(ModuleInfo, _PredInfo, PredId) = Pieces :-
    PredPieces = describe_one_pred_name(ModuleInfo, should_not_module_qualify,
        PredId),
    Pieces = [words("In")] ++ PredPieces ++ [suffix(":"), nl].

:- func error_inconsistent_promise(module_info, pred_info, pred_id, purity)
    = error_spec.

error_inconsistent_promise(ModuleInfo, PredInfo, PredId, Purity) = Spec :-
    pred_info_get_context(PredInfo, Context),
    PredOrFunc = pred_info_is_pred_or_func(PredInfo),
    PredOrFuncStr = pred_or_func_to_full_str(PredOrFunc),
    purity_name(Purity, PurityName),
    PredContextPieces = pred_context(ModuleInfo, PredInfo, PredId),
    MainPieces = PredContextPieces ++
        [words("error: declared"), fixed(PurityName),
        words("but promised pure.")],
    VerbosePieces = [words("A pure"), fixed(PredOrFuncStr),
        words("that invokes impure or semipure code"),
        words("should be promised pure and should have"),
        words("no impurity declaration.")],
    Msg = simple_msg(Context,
        [always(MainPieces), verbose_only(VerbosePieces)]),
    Spec = error_spec(severity_error, phase_purity_check, [Msg]).

:- func warn_exaggerated_impurity_decl(module_info, pred_info, pred_id,
    purity, purity) = error_spec.

warn_exaggerated_impurity_decl(ModuleInfo, PredInfo, PredId,
        DeclPurity, ActualPurity) = Spec :-
    pred_info_get_context(PredInfo, Context),
    PredContextPieces = pred_context(ModuleInfo, PredInfo, PredId),
    purity_name(DeclPurity, DeclPurityName),
    purity_name(ActualPurity, ActualPurityName),
    Pieces = PredContextPieces ++
        [words("warning: declared"), fixed(DeclPurityName),
        words("but actually"), fixed(ActualPurityName ++ ".")],
    Msg = simple_msg(Context, [always(Pieces)]),
    Spec = error_spec(severity_warning, phase_purity_check, [Msg]).

:- func warn_unnecessary_promise_pure(module_info, pred_info, pred_id, purity)
    = error_spec.

warn_unnecessary_promise_pure(ModuleInfo, PredInfo, PredId, PromisedPurity)
        = Spec :-
    pred_info_get_context(PredInfo, Context),
    PredContextPieces = pred_context(ModuleInfo, PredInfo, PredId),
    (
        PromisedPurity = purity_pure,
        Pragma = "promise_pure",
        CodeStr = "impure or semipure"
    ;
        PromisedPurity = purity_semipure,
        Pragma = "promise_semipure",
        CodeStr = "impure"
    ;
        PromisedPurity = purity_impure,
        unexpected($module, $pred, "promise_impure")
    ),
    PredOrFunc = pred_info_is_pred_or_func(PredInfo),
    MainPieces = [words("warning: unnecessary"), quote(Pragma),
        words("pragma."), nl],
    VerbosePieces = [words("This"), p_or_f(PredOrFunc),
        words("does not invoke any"), fixed(CodeStr), words("code,"),
        words("so there is no need for a"), quote(Pragma), words("pragma."),
        nl],
    Msg = simple_msg(Context,
        [always(PredContextPieces), always(MainPieces),
            verbose_only(VerbosePieces)]),
    Spec = error_spec(severity_warning, phase_purity_check, [Msg]).

:- func error_inferred_impure(module_info, pred_info, pred_id, purity)
    = error_spec.

error_inferred_impure(ModuleInfo, PredInfo, PredId, Purity) = Spec :-
    pred_info_get_context(PredInfo, Context),
    PredOrFunc = pred_info_is_pred_or_func(PredInfo),
    PredOrFuncStr = pred_or_func_to_full_str(PredOrFunc),
    PredContextPieces = pred_context(ModuleInfo, PredInfo, PredId),
    pred_info_get_purity(PredInfo, DeclaredPurity),
    purity_name(Purity, PurityName),
    purity_name(DeclaredPurity, DeclaredPurityName),

    Pieces1 = [words("purity error:"), fixed(PredOrFuncStr),
        words("is"), fixed(PurityName), suffix("."), nl],
    ( is_unify_or_compare_pred(PredInfo) ->
        Pieces2 = [words("It must be pure.")]
    ;
        Pieces2 = [words("It must be declared"), quote(PurityName),
            words("or promised"), fixed(DeclaredPurityName ++ "."), nl]
    ),
    Msg = simple_msg(Context,
        [always(PredContextPieces), always(Pieces1), always(Pieces2)]),
    Spec = error_spec(severity_error, phase_purity_check, [Msg]).

:- func error_missing_body_impurity_decl(module_info, pred_id, prog_context)
    = error_spec.

error_missing_body_impurity_decl(ModuleInfo, PredId, Context) = Spec :-
    module_info_pred_info(ModuleInfo, PredId, PredInfo),
    PredOrFunc = pred_info_is_pred_or_func(PredInfo),
    pred_info_get_purity(PredInfo, Purity),
    purity_name(Purity, PurityName),
    PredPieces = describe_one_pred_name(ModuleInfo, should_module_qualify,
        PredId),
    Pieces1 = [words("In call to "), fixed(PurityName)] ++
        PredPieces ++ [suffix(":"), nl],
    (
        PredOrFunc = pf_predicate,
        Pieces2 = [words("purity error: call must be preceded by"),
            quote(PurityName), words("indicator."), nl]
    ;
        PredOrFunc = pf_function,
        Pieces2 = [words("purity error: call must be in"),
            words("an explicit unification which is preceded by"),
            quote(PurityName), words("indicator."), nl]
    ),
    Msg = simple_msg(Context, [always(Pieces1), always(Pieces2)]),
    Spec = error_spec(severity_error, phase_purity_check, [Msg]).

:- func warn_unnecessary_body_impurity_decl(module_info, pred_id, prog_context,
    purity) = error_spec.

warn_unnecessary_body_impurity_decl(ModuleInfo, PredId, Context,
        DeclaredPurity) = Spec :-
    module_info_pred_info(ModuleInfo, PredId, PredInfo),
    pred_info_get_purity(PredInfo, ActualPurity),
    purity_name(DeclaredPurity, DeclaredPurityName),
    purity_name(ActualPurity, ActualPurityName),
    PredPieces = describe_one_pred_name(ModuleInfo, should_module_qualify,
        PredId),

    Pieces1 = [words("In call to")] ++ PredPieces ++ [suffix(":"), nl,
        words("warning: unnecessary"), quote(DeclaredPurityName),
        words("indicator."), nl],
    (
        ActualPurity = purity_pure,
        Pieces2 = [words("No purity indicator is necessary."), nl]
    ;
        ( ActualPurity = purity_impure
        ; ActualPurity = purity_semipure
        ),
        Pieces2 = [words("A purity indicator of"), quote(ActualPurityName),
            words("is sufficient."), nl]
    ),
    Msg = simple_msg(Context, [always(Pieces1), always(Pieces2)]),
    Spec = error_spec(severity_warning, phase_purity_check, [Msg]).

:- func warn_redundant_promise_purity(prog_context, purity, purity)
    = error_spec.

warn_redundant_promise_purity(Context, PromisedPurity, InsidePurity) = Spec :-
    purity_name(PromisedPurity, PromisedPurityName),
    DeclName = "promise_" ++ PromisedPurityName,
    purity_name(InsidePurity, InsidePurityName),
    Pieces = [words("Warning: unnecessary"), quote(DeclName),
        words("goal."), nl,
        words("The purity inside is"), words(InsidePurityName), nl],
    Msg = simple_msg(Context, [always(Pieces)]),
    Spec = error_spec(severity_warning, phase_purity_check, [Msg]).

:- func report_error_closure_purity(prog_context, purity, purity) = error_spec.

report_error_closure_purity(Context, _DeclaredPurity, ActualPurity) = Spec :-
    purity_name(ActualPurity, ActualPurityName),
    Pieces = [words("Purity error in closure: closure body is"),
        fixed(ActualPurityName), suffix(","),
        words("but closure was not declared"),
        fixed(ActualPurityName), suffix("."), nl],
    Msg = simple_msg(Context, [always(Pieces)]),
    Spec = error_spec(severity_error, phase_purity_check, [Msg]).

impure_unification_expr_error(Context, Purity) = Spec :-
    purity_name(Purity, PurityName),
    Pieces = [words("Purity error: unification with expression"),
        words("was declared"), fixed(PurityName ++ ","),
        words("but expression was not a function call.")],
    Msg = simple_msg(Context, [always(Pieces)]),
    Spec = error_spec(severity_error, phase_purity_check, [Msg]).

:- func impure_parallel_conjunct_error(prog_context, purity) = error_spec.

impure_parallel_conjunct_error(Context, Purity) = Spec :-
    purity_name(Purity, PurityName),
    Pieces = [words("Purity error: parallel conjunct is"),
        fixed(PurityName ++ ","),
        words("but parallel conjuncts must be pure or semipure.")],
    Msg = simple_msg(Context, [always(Pieces)]),
    Spec = error_spec(severity_error, phase_purity_check, [Msg]).

:- func bad_outer_var_type_error(prog_context, prog_varset, prog_var)
    = error_spec.

bad_outer_var_type_error(Context, VarSet, Var) = Spec :-
    Pieces = [words("The type of outer variable"),
        fixed(mercury_var_to_string(VarSet, no, Var)),
        words("must be either io.state or stm_builtin.stm.")],
    Msg = simple_msg(Context, [always(Pieces)]),
    Spec = error_spec(severity_error, phase_type_check, [Msg]).

:- func mismatched_outer_var_types(prog_context) = error_spec.

mismatched_outer_var_types(Context) = Spec :-
    Pieces = [words("The types of the two outer variables differ.")],
    Msg = simple_msg(Context, [always(Pieces)]),
    Spec = error_spec(severity_error, phase_type_check, [Msg]).

%-----------------------------------------------------------------------------%

:- type run_post_typecheck
    --->    run_post_typecheck
    ;       do_not_run_post_typecheck.

:- type converted_unify
    --->    have_not_converted_unify
    ;       have_converted_unify.

:- type purity_info
    --->    purity_info(
                % Fields not changed by purity checking.
                pi_module_info          :: module_info,
                pi_run_post_typecheck   :: run_post_typecheck,

                % Fields which may be changed.
                pi_pred_info            :: pred_info,
                pi_vartypes             :: vartypes,
                pi_varset               :: prog_varset,
                pi_messages             :: list(error_spec),
                pi_requant              :: need_to_requantify,
                pi_converted_unify      :: converted_unify
            ).

:- pred purity_info_add_message(error_spec::in,
    purity_info::in, purity_info::out) is det.

purity_info_add_message(Spec, !Info) :-
    Msgs0 = !.Info ^ pi_messages,
    Msgs = [Spec | Msgs0],
    !Info ^ pi_messages := Msgs.

:- pred purity_info_add_messages(list(error_spec)::in,
    purity_info::in, purity_info::out) is det.

purity_info_add_messages(Specs, !Info) :-
    (
        Specs = []
    ;
        Specs = [_ | _],
        Msgs0 = !.Info ^ pi_messages,
        Msgs = Specs ++ Msgs0,
        !Info ^ pi_messages := Msgs
    ).

%-----------------------------------------------------------------------------%
:- end_module check_hlds.purity.
%-----------------------------------------------------------------------------%
