%----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%----------------------------------------------------------------------------%
% Copyright (C) 2014 The Mercury team.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%----------------------------------------------------------------------------%
%
% File: simplify_goal_switch.m.
%
% This module handles simplification of switches.
%
%----------------------------------------------------------------------------%

:- module check_hlds.simplify.simplify_goal_switch.
:- interface.

:- import_module check_hlds.simplify.common.
:- import_module check_hlds.simplify.simplify_info.
:- import_module hlds.
:- import_module hlds.hlds_goal.
:- import_module hlds.instmap.

    % Handle simplifications of switches.
    %
:- pred simplify_goal_switch(
    hlds_goal_expr::in(goal_expr_switch), hlds_goal_expr::out,
    hlds_goal_info::in, hlds_goal_info::out,
    simplify_nested_context::in, instmap::in,
    common_info::in, common_info::out,
    simplify_info::in, simplify_info::out) is det.

%----------------------------------------------------------------------------%

:- implementation.

:- import_module check_hlds.det_util.
:- import_module check_hlds.inst_match.
:- import_module check_hlds.simplify.simplify_goal.
:- import_module check_hlds.type_util.
:- import_module hlds.make_goal.
:- import_module parse_tree.
:- import_module parse_tree.prog_data.
:- import_module parse_tree.prog_mode.
:- import_module parse_tree.prog_type.
:- import_module parse_tree.prog_util.
:- import_module parse_tree.set_of_var.
:- import_module transform_hlds.
:- import_module transform_hlds.pd_cost.

:- import_module bool.
:- import_module list.
:- import_module maybe.
:- import_module pair.
:- import_module require.
:- import_module varset.

simplify_goal_switch(GoalExpr0, GoalExpr, GoalInfo0, GoalInfo,
        NestedContext0, InstMap0, Common0, Common, !Info) :-
    GoalExpr0 = switch(Var, SwitchCanFail0, Cases0),
    simplify_info_get_module_info(!.Info, ModuleInfo0),
    instmap_lookup_var(InstMap0, Var, VarInst),
    simplify_info_get_var_types(!.Info, VarTypes),
    ( inst_is_bound_to_functors(ModuleInfo0, VarInst, BoundInsts) ->
        lookup_var_type(VarTypes, Var, VarType),
        type_to_ctor_det(VarType, VarTypeCtor),
        list.map(bound_inst_to_cons_id(VarTypeCtor), BoundInsts, ConsIds0),
        list.sort(ConsIds0, ConsIds),
        delete_unreachable_cases(Cases0, ConsIds, Cases1),
        MaybeConsIds = yes(ConsIds)
    ;
        Cases1 = Cases0,
        MaybeConsIds = no
    ),
    simplify_switch_cases(Var, Cases1, [], RevCases, [], RevInstMapDeltas,
        not_seen_non_ground_term, SeenNonGroundTerm,
        SwitchCanFail0, SwitchCanFail, NestedContext0, InstMap0, Common0,
        !Info),
    list.reverse(RevCases, Cases),
    (
        Cases = []
    ->
        % An empty switch always fails.
        simplify_info_incr_cost_delta(cost_of_eliminate_switch, !Info),
        Context = goal_info_get_context(GoalInfo0),
        hlds_goal(GoalExpr, GoalInfo) = fail_goal_with_context(Context)
    ;
        Cases = [case(MainConsId, OtherConsIds, SingleGoal)],
        OtherConsIds = []
    ->
        % A singleton switch is equivalent to the goal itself with a
        % possibly can_fail unification with the functor on the front.
        MainConsIdArity = cons_id_arity(MainConsId),
        (
            SwitchCanFail = can_fail,
            MaybeConsIds \= yes([MainConsId])
        ->
            % Don't optimize in the case of an existentially typed constructor
            % because currently create_test_unification does not handle the
            % existential type variables in the types of the constructor
            % arguments or their typeinfos.

            lookup_var_type(VarTypes, Var, Type),
            simplify_info_get_module_info(!.Info, ModuleInfo1),
            ( cons_id_is_existq_cons(ModuleInfo1, Type, MainConsId) ->
                GoalExpr = switch(Var, SwitchCanFail, Cases),
                NonLocals = goal_info_get_nonlocals(GoalInfo0),
                merge_instmap_deltas(InstMap0, NonLocals, VarTypes,
                    RevInstMapDeltas, NewDelta, ModuleInfo1, ModuleInfo2),
                simplify_info_set_module_info(ModuleInfo2, !Info),
                goal_info_set_instmap_delta(NewDelta, GoalInfo0, GoalInfo)
            ;
                create_test_unification(Var, MainConsId, MainConsIdArity,
                    UnifyGoal, InstMap0, !Info),

                % Conjoin the test and the rest of the case.
                goal_to_conj_list(SingleGoal, SingleGoalConj),
                GoalList = [UnifyGoal | SingleGoalConj],

                % Work out the nonlocals, instmap_delta
                % and determinism of the entire conjunction.
                NonLocals0 = goal_info_get_nonlocals(GoalInfo0),
                set_of_var.insert(Var, NonLocals0, NonLocals),
                InstMapDelta0 = goal_info_get_instmap_delta(GoalInfo0),
                instmap_delta_bind_var_to_functor(Var, Type, MainConsId,
                    InstMap0, InstMapDelta0, InstMapDelta,
                    ModuleInfo1, ModuleInfo),
                simplify_info_set_module_info(ModuleInfo, !Info),
                CaseDetism = goal_info_get_determinism(GoalInfo0),
                det_conjunction_detism(detism_semi, CaseDetism, Detism),
                goal_list_purity(GoalList, Purity),
                goal_info_init(NonLocals, InstMapDelta, Detism, Purity,
                    CombinedGoalInfo),

                simplify_info_set_should_requantify(!Info),
                GoalExpr = conj(plain_conj, GoalList),
                GoalInfo = CombinedGoalInfo
            )
        ;
            % The var can only be bound to this cons_id, so a test
            % is unnecessary.
            SingleGoal = hlds_goal(GoalExpr, GoalInfo)
        ),
        simplify_info_incr_cost_delta(cost_of_eliminate_switch, !Info)
    ;
        GoalExpr = switch(Var, SwitchCanFail, Cases),
        (
            ( goal_info_has_feature(GoalInfo0, feature_mode_check_clauses_goal)
            ; SeenNonGroundTerm = not_seen_non_ground_term
            )
        ->
            % Recomputing the instmap delta would take very long and is
            % very unlikely to get any better precision.
            GoalInfo = GoalInfo0
        ;
            simplify_info_get_module_info(!.Info, ModuleInfo1),
            NonLocals = goal_info_get_nonlocals(GoalInfo0),
            merge_instmap_deltas(InstMap0, NonLocals, VarTypes,
                RevInstMapDeltas, NewDelta, ModuleInfo1, ModuleInfo2),
            simplify_info_set_module_info(ModuleInfo2, !Info),
            goal_info_set_instmap_delta(NewDelta, GoalInfo0, GoalInfo)
        )
    ),
    % Any information that is in the updated Common at the end of a switch arm
    % is valid only for that arm. We cannot use that information after the
    % switch as a whole unless the switch turns out to have only one arm.
    % Currently, simplify_switch_cases does not bother returning the commons
    % at the ends of arms, since we expect one-arm switches to be so rare
    % that they are not worth optimizing.
    Common = Common0,
    list.length(Cases0, Cases0Length),
    list.length(Cases, CasesLength),
    ( CasesLength = Cases0Length ->
        true
    ;
        % If we pruned some cases, variables used by those cases may no longer
        % be nonlocal to the switch. Also, the determinism may have changed
        % (especially if we pruned all the cases). If the switch now can't
        % succeed, we have to recompute instmap_deltas and rerun determinism
        % analysis to avoid aborts in the code generator because the switch
        % now cannot produce variables it did before.

        simplify_info_set_should_requantify(!Info),
        simplify_info_set_should_rerun_det(!Info)
    ).

%---------------------------------------------------------------------------%

:- type seen_non_ground_term
    --->    not_seen_non_ground_term
    ;       seen_non_ground_term.

:- pred simplify_switch_cases(prog_var::in, list(case)::in, list(case)::in,
    list(case)::out, list(instmap_delta)::in, list(instmap_delta)::out,
    seen_non_ground_term::in, seen_non_ground_term::out,
    can_fail::in, can_fail::out, simplify_nested_context::in, instmap::in,
    common_info::in, simplify_info::in, simplify_info::out) is det.

simplify_switch_cases(_, [], !RevCases, !RevInstMapDeltas,
        !SeenNonGroundTerm, !CanFail, _NestedContext0, _InstMap0, _Common0,
        !Info).
simplify_switch_cases(Var, [Case0 | Cases0], !RevCases, !RevInstMapDeltas,
        !SeenNonGroundTerm, !CanFail, NestedContext0, InstMap0, Common0,
        !Info) :-
    Case0 = case(MainConsId, OtherConsIds, Goal0),
    simplify_info_get_module_info(!.Info, ModuleInfo0),
    simplify_info_get_var_types(!.Info, VarTypes),
    lookup_var_type(VarTypes, Var, Type),
    bind_var_to_functors(Var, Type, MainConsId, OtherConsIds,
        InstMap0, CaseInstMap0, ModuleInfo0, ModuleInfo1),
    simplify_info_set_module_info(ModuleInfo1, !Info),
    simplify_goal(Goal0, Goal, NestedContext0, CaseInstMap0,
        Common0, _Common1, !Info),

    % Remove failing branches.
    ( Goal = hlds_goal(disj([]), _) ->
        % We don't add the case to RevCases.
        !:CanFail = can_fail
    ;
        Case = case(MainConsId, OtherConsIds, Goal),
        Goal = hlds_goal(GoalExpr, GoalInfo),
        (
            GoalExpr = scope(Reason, _),
            Reason = from_ground_term(_, from_ground_term_construct)
        ->
            % Leave SeenNonGroundTerm as it is.
            true
        ;
            !:SeenNonGroundTerm = seen_non_ground_term
        ),

        % Make sure the switched on variable appears in the instmap delta.
        % This avoids an abort in merge_instmap_delta if another branch
        % further instantiates the switched-on variable. If the switched on
        % variable does not appear in this branch's instmap_delta, the inst
        % before the goal would be used, resulting in a mode error.

        InstMapDelta0 = goal_info_get_instmap_delta(GoalInfo),
        simplify_info_get_module_info(!.Info, ModuleInfo2),
        instmap_delta_bind_var_to_functors(Var, Type, MainConsId, OtherConsIds,
            InstMap0, InstMapDelta0, InstMapDelta, ModuleInfo2, ModuleInfo),
        simplify_info_set_module_info(ModuleInfo, !Info),

        !:RevInstMapDeltas = [InstMapDelta | !.RevInstMapDeltas],
        !:RevCases = [Case | !.RevCases]
    ),

    simplify_switch_cases(Var, Cases0, !RevCases, !RevInstMapDeltas,
        !SeenNonGroundTerm, !CanFail, NestedContext0, InstMap0, Common0,
        !Info).

    % Create a semidet unification at the start of a singleton case
    % in a can_fail switch.
    % This will abort if the cons_id is existentially typed.
    %
:- pred create_test_unification(prog_var::in, cons_id::in, int::in,
    hlds_goal::out, instmap::in, simplify_info::in, simplify_info::out) is det.

create_test_unification(Var, ConsId, ConsArity, ExtraGoal, InstMap0, !Info) :-
    simplify_info_get_varset(!.Info, VarSet0),
    simplify_info_get_var_types(!.Info, VarTypes0),
    varset.new_vars(ConsArity, ArgVars, VarSet0, VarSet),
    lookup_var_type(VarTypes0, Var, VarType),
    simplify_info_get_module_info(!.Info, ModuleInfo),
    type_util.get_cons_id_arg_types(ModuleInfo, VarType, ConsId, ArgTypes),
    vartypes_add_corresponding_lists(ArgVars, ArgTypes, VarTypes0, VarTypes),
    simplify_info_set_varset(VarSet, !Info),
    simplify_info_set_var_types(VarTypes, !Info),
    instmap_lookup_var(InstMap0, Var, Inst0),
    (
        inst_expand(ModuleInfo, Inst0, Inst1),
        get_arg_insts(Inst1, ConsId, ConsArity, ArgInsts1)
    ->
        ArgInsts = ArgInsts1
    ;
        unexpected($module, $pred, "get_arg_insts failed")
    ),
    InstToUniMode =
        (pred(ArgInst::in, ArgUniMode::out) is det :-
            ArgUniMode = ((ArgInst - free) -> (ArgInst - ArgInst))
        ),
    list.map(InstToUniMode, ArgInsts, UniModes),
    UniMode = (Inst0 -> Inst0) - (Inst0 -> Inst0),
    UnifyContext = unify_context(umc_explicit, []),
    Unification = deconstruct(Var, ConsId, ArgVars, UniModes, can_fail,
        cannot_cgc),
    ExtraGoalExpr = unify(Var,
        rhs_functor(ConsId, is_not_exist_constr, ArgVars),
        UniMode, Unification, UnifyContext),
    NonLocals = set_of_var.make_singleton(Var),

    % The test can't bind any variables, so the InstMapDelta should be empty.
    instmap_delta_init_reachable(InstMapDelta),
    goal_info_init(NonLocals, InstMapDelta, detism_semi, purity_pure,
        ExtraGoalInfo),
    ExtraGoal = hlds_goal(ExtraGoalExpr, ExtraGoalInfo).

%---------------------------------------------------------------------------%
:- end_module check_hlds.simplify.simplify_goal_switch.
%---------------------------------------------------------------------------%
