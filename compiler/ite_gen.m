%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%
% Copyright (C) 1994-2011 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% File: ite_gen.m.
% Main authors: conway, fjh, zs.
%
% The predicates of this module generate code for if-then-elses, and for
% negations (which are cut-down versions of if-then-elses, since not(G)
% is equivalent to (G -> fail ; true)).
%
%---------------------------------------------------------------------------%

:- module ll_backend.ite_gen.
:- interface.

:- import_module hlds.code_model.
:- import_module hlds.hlds_goal.
:- import_module ll_backend.code_info.
:- import_module ll_backend.llds.

%---------------------------------------------------------------------------%

:- pred generate_ite(code_model::in,
    hlds_goal::in, hlds_goal::in, hlds_goal::in, hlds_goal_info::in,
    llds_code::out, code_info::in, code_info::out) is det.

:- pred generate_negation(code_model::in, hlds_goal::in, hlds_goal_info::in,
    llds_code::out, code_info::in, code_info::out) is det.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module backend_libs.builtin_ops.
:- import_module hlds.goal_form.
:- import_module hlds.hlds_llds.
:- import_module hlds.hlds_module.
:- import_module hlds.hlds_pred.
:- import_module hlds.instmap.
:- import_module libs.globals.
:- import_module libs.options.
:- import_module ll_backend.code_gen.
:- import_module ll_backend.continuation_info.
:- import_module ll_backend.opt_debug.
:- import_module ll_backend.trace_gen.
:- import_module mdbcomp.builtin_modules.
:- import_module parse_tree.prog_data.
:- import_module parse_tree.set_of_var.
:- import_module transform_hlds.
:- import_module transform_hlds.rbmm.
:- import_module transform_hlds.rbmm.region_transformation.

:- import_module bool.
:- import_module cord.
:- import_module int.
:- import_module io.
:- import_module list.
:- import_module map.
:- import_module maybe.
:- import_module require.
:- import_module set.
:- import_module string.
:- import_module term.

%---------------------------------------------------------------------------%

generate_ite(CodeModel, CondGoal0, ThenGoal, ElseGoal, IteGoalInfo, Code,
        !CI) :-
    CondGoal0 = hlds_goal(CondExpr, CondInfo0),
    CondCodeModel = goal_info_get_code_model(CondInfo0),
    (
        CodeModel = model_non,
        CondCodeModel \= model_non
    ->
        EffCodeModel = model_semi
    ;
        EffCodeModel = CodeModel
    ),

    goal_info_get_resume_point(CondInfo0, Resume),
    (
        Resume = resume_point(ResumeVarsPrime, ResumeLocsPrime),
        ResumeVars = ResumeVarsPrime,
        ResumeLocs = ResumeLocsPrime,
        % The pre_goal_update sanity check insists on no_resume_point,
        % to make sure that all resume points have been handled by
        % surrounding code.
        goal_info_set_resume_point(no_resume_point, CondInfo0, CondInfo),
        CondGoal = hlds_goal(CondExpr, CondInfo)
    ;
        Resume = no_resume_point,
        unexpected($module, $pred,
            "condition of an if-then-else has no resume point")
    ),

    % Make sure that the variables whose values will be needed on backtracking
    % to the else part are materialized into registers or stack slots.
    % Their locations are recorded in ResumeMap.
    produce_vars(set_of_var.to_sorted_list(ResumeVars), ResumeMap,
        FlushCode, !CI),

    % Maybe save the heap state current before the condition.
    % This is after produce_vars since code that flushes the cache
    % may allocate memory we must not "recover".
    get_globals(!.CI, Globals),
    globals.lookup_bool_option(Globals, reclaim_heap_on_semidet_failure,
        ReclaimOption),
    (
        ReclaimOption = yes,
        goal_may_allocate_heap(CondGoal)
    ->
        ReclaimHeap = yes
    ;
        ReclaimHeap = no
    ),
    maybe_save_hp(ReclaimHeap, SaveHpCode, MaybeHpSlot, !CI),

    % Maybe save the current trail state before the condition.
    % NOTE: This code should be kept up-to-date with the corresponding code
    % for the MLDS backend in add_trail_ops.m.
    AddTrailOps = should_add_trail_ops(!.CI, IteGoalInfo),
    (
        AddTrailOps = do_not_add_trail_ops,
        IteTrailOps = do_not_add_trail_ops
    ;
        AddTrailOps = add_trail_ops,
        get_opt_trail_ops(!.CI, OptTrailOps),
        (
            OptTrailOps = yes,
            goal_cannot_modify_trail(CondInfo0) = yes,
            CondCodeModel \= model_non
        ->
            IteTrailOps = do_not_add_trail_ops
        ;
            IteTrailOps = add_trail_ops
        )
    ),
    maybe_save_ticket(IteTrailOps, SaveTicketCode, MaybeTicketSlot, !CI),

    % XXX Consider optimizing IteRegionOps like IteTrailOps.
    AddRegionOps = should_add_region_ops(!.CI, IteGoalInfo),
    IteRegionOps = AddRegionOps,
    goal_to_conj_list(ElseGoal, ElseGoals),
    goal_to_conj_list(CondGoal, CondGoals),
    maybe_create_ite_region_frame(IteRegionOps, CondInfo, CondGoals, ElseGoals,
        RegionCondCode, RegionThenCode, RegionElseCode, RegionStackVars,
        MaybeEmbeddedStackFrameId, !CI),

    remember_position(!.CI, BranchStart),

    prepare_for_ite_hijack(CondCodeModel, MaybeEmbeddedStackFrameId,
        HijackInfo, PrepareHijackCode, !CI),

    make_resume_point(set_of_var.to_sorted_list(ResumeVars),
        ResumeLocs, ResumeMap, ResumePoint, !CI),
    effect_resume_point(ResumePoint, EffCodeModel, EffectResumeCode, !CI),

    % Generate the condition.
    maybe_generate_internal_event_code(CondGoal, IteGoalInfo, CondTraceCode,
        !CI),
    generate_goal(CondCodeModel, CondGoal, CondCode, !CI),

    ite_enter_then(HijackInfo, ResumePoint, ThenNeckCode, ElseNeckCode, !CI),

    % Kill again any variables that have become zombies.
    pickup_zombies(Zombies, !CI),
    make_vars_forward_dead(Zombies, !CI),

    % Discard hp and prune trail ticket if the condition succeeded.
    (
        CondCodeModel = model_non,
        % We cannot release the stack slots used for the heap pointer
        % and the trail ticket if the condition can be backtracked
        % into.  Nor can we prune the trail ticket that we allocated,
        % since the condition may have allocated other trail tickets
        % since then which have not yet been pruned.
        %
        % We also cannot release RegionStackVars.
        maybe_reset_ticket(MaybeTicketSlot, reset_reason_solve,
            ResetTicketCode)
    ;
        ( CondCodeModel = model_det
        ; CondCodeModel = model_semi
        ),
        maybe_release_hp(MaybeHpSlot, !CI),
        maybe_reset_prune_and_release_ticket(MaybeTicketSlot,
            reset_reason_commit, ResetTicketCode, !CI),

        release_several_temp_slots(RegionStackVars, non_persistent_temp_slot,
            !CI)
    ),

    goal_info_get_store_map(IteGoalInfo, StoreMap),
    get_instmap(!.CI, EndCondInstMap),
    ( instmap_is_unreachable(EndCondInstMap) ->
        % If the instmap indicates we cannot reach the then part,
        % do not attempt to generate it (may cause aborts).
        ThenTraceCode = empty,
        ThenCode = empty,
        map.init(EmptyStoreMap),
        generate_branch_end(EmptyStoreMap, no, MaybeEnd0, ThenSaveCode, !CI)
    ;
        % Generate the then branch.
        maybe_generate_internal_event_code(ThenGoal, IteGoalInfo,
            ThenTraceCode, !CI),
        code_gen.generate_goal(CodeModel, ThenGoal, ThenCode, !CI),
        generate_branch_end(StoreMap, no, MaybeEnd0, ThenSaveCode, !CI)
    ),

    % Generate the entry to the else branch.
    reset_to_position(BranchStart, !CI),
    generate_resume_point(ResumePoint, ResumeCode, !CI),

    trace [compiletime(flag("codegen_goal")), io(!S)] (
        ( should_trace_code_gen(!.CI) ->
            ResumeInstrs = cord.list(ResumeCode),
            io.write_string("\nRESUME INSTRS:\n", !S),
            write_instrs(ResumeInstrs, no, yes, !S)
        ;
            true
        )
    ),

    % Restore the heap pointer and solver state if necessary.
    maybe_restore_and_release_hp(MaybeHpSlot, RestoreHpCode, !CI),
    maybe_reset_discard_and_release_ticket(MaybeTicketSlot,
        reset_reason_undo, RestoreTicketCode, !CI),

    % Generate the else branch.
    maybe_generate_internal_event_code(ElseGoal, IteGoalInfo, ElseTraceCode,
        !CI),
    code_gen.generate_goal(CodeModel, ElseGoal, ElseCode, !CI),
    generate_branch_end(StoreMap, MaybeEnd0, MaybeEnd, ElseSaveCode, !CI),

    trace [compiletime(flag("codegen_goal")), io(!S)] (
        ( should_trace_code_gen(!.CI) ->
            ElseSaveInstrs = cord.list(ElseSaveCode),
            io.write_string("\nBRANCH END INSTRS:\n", !S),
            write_instrs(ElseSaveInstrs, no, yes, !S)
        ;
            true
        )
    ),

    get_next_label(EndLabel, !CI),
    JumpToEndCode = singleton(
        llds_instr(goto(code_label(EndLabel)),
            "Jump to the end of if-then-else")
    ),
    EndLabelCode = singleton(
        llds_instr(label(EndLabel), "end of if-then-else")
    ),
    make_pneg_context_wrappers(Globals, CondInfo, PNegCondCode, PNegThenCode,
        PNegElseCode),
    Code =
        FlushCode ++
        SaveHpCode ++
        SaveTicketCode ++
        RegionCondCode ++
        PrepareHijackCode ++
        EffectResumeCode ++
        CondTraceCode ++
        PNegCondCode ++
        CondCode ++
        ThenNeckCode ++
        ResetTicketCode ++
        RegionThenCode ++
        ThenTraceCode ++
        PNegThenCode ++
        ThenCode ++
        ThenSaveCode ++
        JumpToEndCode ++
        ResumeCode ++
        ElseNeckCode ++
        RestoreHpCode ++
        RestoreTicketCode ++
        RegionElseCode ++
        ElseTraceCode ++
        PNegElseCode ++
        ElseCode ++
        ElseSaveCode ++
        EndLabelCode,
    after_all_branches(StoreMap, MaybeEnd, !CI).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

generate_negation(CodeModel, Goal0, NotGoalInfo, Code, !CI) :-
    (
        CodeModel = model_non,
        unexpected($module, $pred, "nondet negation")
    ;
        ( CodeModel = model_det
        ; CodeModel = model_semi
        )
    ),

    Goal0 = hlds_goal(GoalExpr, GoalInfo0),
    goal_info_get_resume_point(GoalInfo0, Resume),
    (
        Resume = resume_point(ResumeVarsPrime, ResumeLocsPrime),
        ResumeVars = ResumeVarsPrime,
        ResumeLocs = ResumeLocsPrime,
        goal_info_set_resume_point(no_resume_point, GoalInfo0, GoalInfo),
        Goal = hlds_goal(GoalExpr, GoalInfo)
    ;
        Resume = no_resume_point,
        unexpected($module, $pred, "negated goal has no resume point")
    ),

    % For a negated simple test, we can generate better code than the general
    % mechanism, because we don't have to flush the cache.
    (
        CodeModel = model_semi,
        GoalExpr = unify(_, _, _, simple_test(L, R), _),
        failure_is_direct_branch(!.CI, CodeAddr),
        get_globals(!.CI, Globals),
        globals.lookup_bool_option(Globals, simple_neg, yes)
    ->
        % Because we are generating the negated goal ourselves, we need to
        % apply the pre- and post-goal updates that would normally be applied
        % by code_gen.generate_goal.

        enter_simple_neg(set_of_var.to_sorted_list(ResumeVars), GoalInfo,
            SimpleNeg, !CI),
        produce_variable(L, CodeL, ValL, !CI),
        produce_variable(R, CodeR, ValR, !CI),
        Type = variable_type(!.CI, L),
        ( Type = builtin_type(builtin_type_string) ->
            Op = str_eq
        ; Type = builtin_type(builtin_type_float) ->
            Op = float_eq
        ;
            Op = eq
        ),
        TestCode = singleton(
            llds_instr(if_val(binop(Op, ValL, ValR), CodeAddr),
                "test inequality")
        ),
        leave_simple_neg(GoalInfo, SimpleNeg, !CI),
        Code = CodeL ++ CodeR ++ TestCode
    ;
        generate_negation_general(CodeModel, Goal, NotGoalInfo,
            ResumeVars, ResumeLocs, Code, !CI)
    ).

    % The code of generate_negation_general is a cut-down version
    % of the code for if-then-elses.
    %
:- pred generate_negation_general(code_model::in,
    hlds_goal::in, hlds_goal_info::in, set_of_progvar::in,
    resume_locs::in, llds_code::out, code_info::in, code_info::out) is det.

generate_negation_general(CodeModel, Goal, NotGoalInfo, ResumeVars, ResumeLocs,
        Code, !CI) :-
    produce_vars(set_of_var.to_sorted_list(ResumeVars), ResumeMap,
        FlushCode, !CI),

    % Maybe save the heap state current before the condition; this ought to be
    % after we make the failure continuation because that causes the cache to
    % get flushed.

    get_globals(!.CI, Globals),
    globals.lookup_bool_option(Globals, reclaim_heap_on_semidet_failure,
        ReclaimHeapOnFailure),
    (
        ReclaimHeapOnFailure = yes,
        goal_may_allocate_heap(Goal)
    ->
        ReclaimHeap = yes
    ;
        ReclaimHeap = no
    ),
    maybe_save_hp(ReclaimHeap, SaveHpCode, MaybeHpSlot, !CI),

    % XXX Consider optimizing AddTrailOps as for if-then-elses.
    AddTrailOps = should_add_trail_ops(!.CI, NotGoalInfo),
    maybe_save_ticket(AddTrailOps, SaveTicketCode, MaybeTicketSlot, !CI),

    % XXX Consider optimizing IteRegionOps like IteTrailOps.
    AddRegionOps = should_add_region_ops(!.CI, NotGoalInfo),
    IteRegionOps = AddRegionOps,
    Goal = hlds_goal(_, GoalInfo),
    goal_to_conj_list(Goal, CondGoals),
    maybe_create_ite_region_frame(IteRegionOps, GoalInfo, CondGoals, [],
        RegionCondCode, RegionThenCode, RegionElseCode, RegionStackVars,
        MaybeRegionSuccRecordSlot, !CI),
    % MaybeRegionSuccRecordSlot should be yes only for nondet conditions,
    % and a negated goal can't be nondet.
    expect(unify(MaybeRegionSuccRecordSlot, no), $module, $pred,
        "MaybeRegionSuccRecordSlot = yes(_)"),

    prepare_for_ite_hijack(CodeModel, MaybeRegionSuccRecordSlot, HijackInfo,
        PrepareHijackCode, !CI),

    make_resume_point(set_of_var.to_sorted_list(ResumeVars),
        ResumeLocs, ResumeMap, ResumePoint, !CI),
    effect_resume_point(ResumePoint, CodeModel, EffectResumeCode, !CI),

    % Generate the negated goal as a semi-deterministic goal; it cannot be
    % nondet, since mode correctness requires it to have no output vars.
    maybe_generate_internal_event_code(Goal, NotGoalInfo, EnterTraceCode, !CI),
    code_gen.generate_goal(model_semi, Goal, GoalCode, !CI),

    ite_enter_then(HijackInfo, ResumePoint, ThenNeckCode, ElseNeckCode, !CI),

    % Kill again any variables that have become zombies.
    pickup_zombies(Zombies, !CI),
    make_vars_forward_dead(Zombies, !CI),

    get_forward_live_vars(!.CI, LiveVars),

    (
        CodeModel = model_det,
        % The then branch will never be reached.
        PruneTicketCode = empty,
        FailTraceCode = empty,
        FailCode = empty
    ;
        ( CodeModel = model_semi
        ; CodeModel = model_non
        ),
        remember_position(!.CI, AfterNegatedGoal),
        % The call to reset_ticket(..., commit) here is necessary
        % in order to properly detect floundering.
        maybe_release_hp(MaybeHpSlot, !CI),
        maybe_reset_prune_and_release_ticket(MaybeTicketSlot,
            reset_reason_commit, PruneTicketCode, !CI),
        maybe_generate_negated_event_code(Goal, NotGoalInfo, neg_failure,
            FailTraceCode, !CI),
        generate_failure(FailCode, !CI),
        % We want liveness after not(G) to be the same as after G.
        % Information about what variables are where will be set
        % by generate_resume_point.
        reset_to_position(AfterNegatedGoal, !CI)
    ),

    % Generate the entry to the else branch.
    generate_resume_point(ResumePoint, ResumeCode, !CI),

    set_forward_live_vars(LiveVars, !CI),

    % Restore the heap pointer and solver state if necessary.
    maybe_restore_and_release_hp(MaybeHpSlot, RestoreHpCode, !CI),
    maybe_reset_discard_and_release_ticket(MaybeTicketSlot,
        reset_reason_undo, RestoreTicketCode, !CI),
    release_several_temp_slots(RegionStackVars,
        non_persistent_temp_slot, !CI),
    maybe_generate_negated_event_code(Goal, NotGoalInfo, neg_success,
        SuccessTraceCode, !CI),

    make_pneg_context_wrappers(Globals, NotGoalInfo, PNegCondCode,
        PNegThenCode, PNegElseCode),
    Code =
        FlushCode ++
        PrepareHijackCode ++
        EffectResumeCode ++
        SaveHpCode ++
        SaveTicketCode ++
        RegionCondCode ++
        EnterTraceCode ++
        PNegCondCode ++
        GoalCode ++
        ThenNeckCode ++
        PruneTicketCode ++
        RegionThenCode ++
        FailTraceCode ++
        PNegThenCode ++
        FailCode ++
        ResumeCode ++
        ElseNeckCode ++
        RestoreTicketCode ++
        RestoreHpCode ++
        RegionElseCode ++
        SuccessTraceCode ++
        PNegElseCode.

%---------------------------------------------------------------------------%

    % If the code in the condition depends on a consumer of a generator
    % that is not complete by the time we finish executing the condition,
    % then failure out of the condition does not necessarily mean that
    % the condition has no solution; it may mean simply that the condition's
    % solution depends on a generator solution that hasn't been produced yet
    % and thus hasn't been given to the consumer yet.
    %
    % Detecting such situations requires knowing whether tabled subgoals
    % (both generators and consumers) are started inside possibly negated
    % contexts or not, which is why we wrap the condition inside
    % MR_pneg_enter_{cond,then,exit}.
    %
:- pred make_pneg_context_wrappers(globals::in, hlds_goal_info::in,
    llds_code::out, llds_code::out, llds_code::out) is det.

make_pneg_context_wrappers(Globals, GoalInfo, PNegCondCode, PNegThenCode,
        PNegElseCode) :-
    globals.lookup_bool_option(Globals, use_minimal_model_stack_copy_pneg,
        UseMinimalModelStackCopyPNeg),
    (
        UseMinimalModelStackCopyPNeg = yes,
        not goal_info_has_feature(GoalInfo, feature_will_not_call_mm_tabled)
    ->
        Context = goal_info_get_context(GoalInfo),
        term.context_file(Context, File),
        term.context_line(Context, Line),
        (
            File \= "",
            Line > 0
        ->
            CtxtStr = "\"" ++ File ++ ":" ++ int_to_string(Line) ++ "\""
        ;
            CtxtStr = "NULL"
        ),

        PNegCondComponents = [
            foreign_proc_raw_code(cannot_branch_away,
                proc_does_not_affect_liveness, live_lvals_info(set.init),
                wrap_transient("\t\tMR_pneg_enter_cond();\n"))
        ],
        PNegThenComponents = [
            foreign_proc_raw_code(cannot_branch_away,
                proc_does_not_affect_liveness, live_lvals_info(set.init),
                wrap_transient("\t\tMR_pneg_enter_then();\n"))
        ],
        PNegElseComponents = [
            foreign_proc_raw_code(cannot_branch_away,
                proc_does_not_affect_liveness, live_lvals_info(set.init),
                wrap_transient("\t\tMR_pneg_enter_else(" ++ CtxtStr ++ ");\n"))
        ],
        MD = proc_may_duplicate,
        PNegCondCode = singleton(
            llds_instr(foreign_proc_code([], PNegCondComponents,
                proc_will_not_call_mercury, no, no, no, no, no, yes, MD), "")
        ),
        PNegThenCode = singleton(
            llds_instr(foreign_proc_code([], PNegThenComponents,
                proc_will_not_call_mercury, no, no, no, no, no, yes, MD), "")
        ),
        PNegElseCode = singleton(
            llds_instr(foreign_proc_code([], PNegElseComponents,
                proc_will_not_call_mercury, no, no, no, no, no, yes, MD), "")
        )
    ;
        PNegCondCode = empty,
        PNegThenCode = empty,
        PNegElseCode = empty
    ).

:- func wrap_transient(string) = string.

wrap_transient(Code) =
    string.append_list([
        "\t\tMR_save_transient_registers();\n",
        Code,
        "\t\tMR_restore_transient_registers();\n"]).

%-----------------------------------------------------------------------------%

:- pred maybe_create_ite_region_frame(add_region_ops::in,
    hlds_goal_info::in, list(hlds_goal)::in, list(hlds_goal)::in,
    llds_code::out, llds_code::out, llds_code::out, list(lval)::out,
    maybe(embedded_stack_frame_id)::out, code_info::in, code_info::out) is det.

maybe_create_ite_region_frame(IteRegionOps, CondGoalInfo, CondGoals, ElseGoals,
        CondCode, ThenCode, ElseCode, StackVars, MaybeEmbeddedStackFrameId,
        !CI) :-
    (
        IteRegionOps = do_not_add_region_ops,
        CondCode = empty,
        ThenCode = empty,
        ElseCode = empty,
        StackVars = [],
        MaybeEmbeddedStackFrameId = no
    ;
        IteRegionOps = add_region_ops,
        get_forward_live_vars(!.CI, ForwardLiveVars),
        LiveRegionVars = filter_region_vars(!.CI, ForwardLiveVars),

        MaybeRbmmInfo = goal_info_get_maybe_rbmm(CondGoalInfo),
        (
            MaybeRbmmInfo = no,
            CondCode = empty,
            ThenCode = empty,
            ElseCode = empty,
            StackVars = [],
            MaybeEmbeddedStackFrameId = no
        ;
            MaybeRbmmInfo = yes(RbmmInfo),
            RbmmInfo = rbmm_goal_info(CondCreatedRegionVars,
                CondRemovedRegionVars, CondCarriedRegionVars,
                CondAllocRegionVars, _CondUsedRegionVars),
            list.reverse(CondGoals, ReversedCondGoals),
            code_info.get_module_info(!.CI, ModuleInfo),
            find_regions_removed_at_start_of_goals(ReversedCondGoals,
                ModuleInfo, set.init, RemovedAtEndOfThen),
            set.difference(CondRemovedRegionVars, RemovedAtEndOfThen,
                NeedToBeProtectedRegionVars),
            (
                set.empty(CondCreatedRegionVars),
                set.empty(NeedToBeProtectedRegionVars),
                set.empty(CondAllocRegionVars)
            ->
                % When no region-related operations occur in the
                % condition we do not need the backtracking support code.
                CondCode = empty,
                ThenCode = empty,
                ElseCode = empty,
                StackVars = [],
                MaybeEmbeddedStackFrameId = no
            ;
                find_regions_removed_at_start_of_goals(ElseGoals, ModuleInfo,
                    set.init, RemovedAtStartOfElse),

                % The UnprotectedRemovedAtStartOfElse is the
                % intersection of RemovedAtStartOfElse and the set of region
                % variables whose regions are statically known to be
                % unprotected at this point in the code. These are actually
                % carried regions because carried region are statically known
                % to be not protected by the condition.
                UnprotectedRemovedAtStartOfElse = set.intersect(
                    RemovedAtStartOfElse, CondCarriedRegionVars),

                ProtectRegionVars = set_of_var.intersect(LiveRegionVars,
                    set_to_bitset(NeedToBeProtectedRegionVars)),
                SnapshotRegionVars0 = set_of_var.intersect(LiveRegionVars,
                    set_to_bitset(CondAllocRegionVars)),
                SnapshotRegionVars = set_of_var.difference(SnapshotRegionVars0,
                    set_to_bitset(UnprotectedRemovedAtStartOfElse)),

                ProtectRegionVarList =
                    set_of_var.to_sorted_list(ProtectRegionVars),
                SnapshotRegionVarList =
                    set_of_var.to_sorted_list(SnapshotRegionVars),

                list.length(ProtectRegionVarList, NumProtectRegionVars),
                list.length(SnapshotRegionVarList, NumSnapshotRegionVars),

                code_info.get_globals(!.CI, Globals),
                globals.lookup_int_option(Globals, size_region_ite_fixed,
                    FixedSize),
                globals.lookup_int_option(Globals, size_region_ite_protect,
                    ProtectSize),
                globals.lookup_int_option(Globals,
                    size_region_ite_snapshot, SnapshotSize),
                FrameSize = FixedSize
                    + ProtectSize * NumProtectRegionVars
                    + SnapshotSize * NumSnapshotRegionVars,

                Items = list.duplicate(FrameSize, slot_region_ite),
                acquire_several_temp_slots(Items, non_persistent_temp_slot,
                    StackVars, MainStackId, FirstSlotNum, LastSlotNum, !CI),
                EmbeddedStackFrameId = embedded_stack_frame_id(MainStackId,
                    FirstSlotNum, LastSlotNum),
                FirstNonFixedAddr = first_nonfixed_embedded_slot_addr(
                    EmbeddedStackFrameId, FixedSize),
                acquire_reg(reg_r, ProtectNumRegLval, !CI),
                acquire_reg(reg_r, SnapshotNumRegLval, !CI),
                acquire_reg(reg_r, AddrRegLval, !CI),
                PushInitCode = from_list([
                    llds_instr(
                        push_region_frame(region_stack_ite,
                            EmbeddedStackFrameId),
                        "Save stack pointer of embedded region ite stack"),
                    llds_instr(
                        assign(ProtectNumRegLval, const(llconst_int(0))),
                        "Initialize number of protect_infos"),
                    llds_instr(
                        assign(SnapshotNumRegLval, const(llconst_int(0))),
                        "Initialize number of snapshot_infos"),
                    llds_instr(
                        assign(AddrRegLval, FirstNonFixedAddr),
                        "Initialize pointer to nonfixed part of" ++
                        " embedded frame")
                ]),
                ite_protect_regions(ProtectNumRegLval, AddrRegLval,
                    EmbeddedStackFrameId, ProtectRegionVarList,
                    ProtectRegionCode, !CI),
                ite_alloc_snapshot_regions(SnapshotNumRegLval, AddrRegLval,
                    EmbeddedStackFrameId, RemovedAtStartOfElse,
                    SnapshotRegionVarList, SnapshotRegionCode, !CI),
                SetCode = from_list([
                    llds_instr(
                        region_set_fixed_slot(region_set_ite_num_protects,
                            EmbeddedStackFrameId, lval(ProtectNumRegLval)),
                        "Store the number of protect_infos"),
                    llds_instr(
                        region_set_fixed_slot(region_set_ite_num_snapshots,
                            EmbeddedStackFrameId, lval(SnapshotNumRegLval)),
                        "Store the number of snapshot_infos")
                ]),
                release_reg(ProtectNumRegLval, !CI),
                release_reg(SnapshotNumRegLval, !CI),
                release_reg(AddrRegLval, !CI),

                CondCodeModel = goal_info_get_code_model(CondGoalInfo),
                (
                    CondCodeModel = model_non,
                    CondKind = region_ite_nondet_cond,
                    MaybeEmbeddedStackFrameId = yes(EmbeddedStackFrameId)
                ;
                    CondCodeModel = model_semi,
                    CondKind = region_ite_semidet_cond,
                    MaybeEmbeddedStackFrameId = no
                ;
                    CondCodeModel = model_det,
                    unexpected($module, $pred, "det cond")
                ),

                CondCode = PushInitCode ++ ProtectRegionCode ++
                    SnapshotRegionCode ++ SetCode,
                ThenCode = singleton(
                    llds_instr(
                        use_and_maybe_pop_region_frame(
                            region_ite_then(CondKind),
                            EmbeddedStackFrameId),
                        "region enter then")
                ),
                ElseCode = singleton(
                    llds_instr(
                        use_and_maybe_pop_region_frame(
                            region_ite_else(CondKind),
                            EmbeddedStackFrameId),
                        "region enter else")
                )

                % XXX A model_non condition can succeed more than once, so
                % the region_ite_then(region_ite_nondet_cond) operation
                % cannot pop the ite stack frame. We need to pop this
                % frame when the condition fails *after* succeeding at
                % least once. This requires modifying the failure
                % continuation and/or the resume point. This has not yet
                % been implemented.
            )
        )
    ).

    % Given the list of goals in the else branch, accumulate the region
    % variables whose regions are removed at the start of that list.
    %
:- pred find_regions_removed_at_start_of_goals(list(hlds_goal)::in,
    module_info::in, set(prog_var)::in, set(prog_var)::out) is det.

find_regions_removed_at_start_of_goals([], _, !Removed).
find_regions_removed_at_start_of_goals([Goal | Goals], ModuleInfo, !Removed) :-
    Goal = hlds_goal(GoalExpr, _),
    (
        GoalExpr = plain_call(PredId, _ProcId, Args, _Builtin, _UC, _SymName),
        module_info_pred_info(ModuleInfo, PredId, PredInfo),
        pred_info_module(PredInfo) = mercury_region_builtin_module,
        pred_info_name(PredInfo) = remove_region_pred_name,
        Args = [RegionVar]
    ->
        set.insert(RegionVar, !Removed),
        find_regions_removed_at_start_of_goals(Goals, ModuleInfo, !Removed)
    ;
        true
    ).

:- pred ite_protect_regions(lval::in, lval::in, embedded_stack_frame_id::in,
    list(prog_var)::in, llds_code::out, code_info::in, code_info::out) is det.

ite_protect_regions(_, _, _, [], empty, !CI).
ite_protect_regions(NumLval, AddrLval, EmbeddedStackFrameId,
        [RegionVar | RegionVars], Code ++ Codes, !CI) :-
    produce_variable(RegionVar, ProduceVarCode, RegionVarRval, !CI),
    SaveCode = singleton(
        llds_instr(
            region_fill_frame(region_fill_ite_protect,
                EmbeddedStackFrameId, RegionVarRval, NumLval, AddrLval),
            "ite protect the region if needed")
    ),
    Code = ProduceVarCode ++ SaveCode,
    ite_protect_regions(NumLval, AddrLval, EmbeddedStackFrameId,
        RegionVars, Codes, !CI).

:- pred ite_alloc_snapshot_regions(lval::in, lval::in,
    embedded_stack_frame_id::in, set(prog_var)::in,
    list(prog_var)::in, llds_code::out, code_info::in, code_info::out) is det.

ite_alloc_snapshot_regions(_, _, _, _, [], empty, !CI).
ite_alloc_snapshot_regions(NumLval, AddrLval, EmbeddedStackFrameId,
        RemovedVars, [RegionVar | RegionVars], Code ++ Codes, !CI) :-
    produce_variable(RegionVar, ProduceVarCode, RegionVarRval, !CI),
    ( set.member(RegionVar, RemovedVars) ->
        RemovedAtStartOfElse = removed_at_start_of_else
    ;
        RemovedAtStartOfElse = not_removed_at_start_of_else
    ),
    SaveCode = singleton(
        llds_instr(
            region_fill_frame(region_fill_ite_snapshot(RemovedAtStartOfElse),
                EmbeddedStackFrameId, RegionVarRval, NumLval, AddrLval),
            "take alloc snapshot of the region")
    ),
    Code = ProduceVarCode ++ SaveCode,
    ite_alloc_snapshot_regions(NumLval, AddrLval, EmbeddedStackFrameId,
        RemovedVars, RegionVars, Codes, !CI).

%-----------------------------------------------------------------------------%
:- end_module ll_backend.ite_gen.
%-----------------------------------------------------------------------------%
