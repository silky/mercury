%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 2014 The Mercury team.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: make_hlds.m.
%
% This module defines predicates that construct HLDS goals.
%
%-----------------------------------------------------------------------------%

:- module hlds.make_goal.

:- interface.

:- import_module hlds.hlds_goal.
:- import_module hlds.hlds_pred.
:- import_module parse_tree.prog_data.

:- import_module char.
:- import_module list.
:- import_module maybe.

    % Return the HLDS equivalent of `true'.
    %
:- func true_goal = hlds_goal.
:- func true_goal_expr = hlds_goal_expr.

:- func true_goal_with_context(prog_context) = hlds_goal.

    % Return the HLDS equivalent of `fail'.
    %
:- func fail_goal = hlds_goal.
:- func fail_goal_expr = hlds_goal_expr.
:- func fail_goal_info = hlds_goal_info.

:- func fail_goal_with_context(prog_context) = hlds_goal.

    % Create the hlds_goal for a unification, filling in all the as yet
    % unknown slots with dummy values. The unification is constructed as a
    % complicated unification; turning it into some other kind of unification,
    % if appropriate is left to mode analysis. Therefore this predicate
    % shouldn't be used unless you know mode analysis will be run on its
    % output.
    %
:- pred create_atomic_complicated_unification(prog_var::in, unify_rhs::in,
    prog_context::in, unify_main_context::in, unify_sub_contexts::in,
    purity::in, hlds_goal::out) is det.

    % As above, but with default purity pure.
    %
:- pred create_pure_atomic_complicated_unification(prog_var::in, unify_rhs::in,
    prog_context::in, unify_main_context::in, unify_sub_contexts::in,
    hlds_goal::out) is det.

    % Create the hlds_goal for a unification that assigns the second variable
    % to the first. The initial inst of the second variable should be
    % ground_inst. The resulting goal has all its fields filled in.
    %
:- pred make_simple_assign(prog_var::in, prog_var::in,
    unify_main_context::in, unify_sub_contexts::in, hlds_goal::out) is det.

    % Create the hlds_goal for a unification that tests the equality of two
    % values of atomic types. The resulting goal has all its fields filled in.
    %
:- pred make_simple_test(prog_var::in, prog_var::in,
    unify_main_context::in, unify_sub_contexts::in, hlds_goal::out) is det.

    % Produce a goal to construct a given constant. These predicates all
    % fill in the non-locals, instmap_delta and determinism fields of the
    % goal_info of the returned goal. With alias tracking, the instmap_delta
    % will be correct only if the variable being assigned to has no aliases.
    %
    % Ths cons_id passed to make_const_construction must be fully module
    % qualified.
    %
:- pred make_int_const_construction(prog_var::in, int::in,
    hlds_goal::out) is det.
:- pred make_string_const_construction(prog_var::in, string::in,
    hlds_goal::out) is det.
:- pred make_float_const_construction(prog_var::in, float::in,
    hlds_goal::out) is det.
:- pred make_char_const_construction(prog_var::in, char::in,
    hlds_goal::out) is det.
:- pred make_const_construction(prog_var::in, cons_id::in,
    hlds_goal::out) is det.

:- pred make_int_const_construction_alloc(int::in, maybe(string)::in,
    hlds_goal::out, prog_var::out,
    prog_varset::in, prog_varset::out, vartypes::in, vartypes::out) is det.
:- pred make_string_const_construction_alloc(string::in, maybe(string)::in,
    hlds_goal::out, prog_var::out,
    prog_varset::in, prog_varset::out, vartypes::in, vartypes::out) is det.
:- pred make_float_const_construction_alloc(float::in, maybe(string)::in,
    hlds_goal::out, prog_var::out,
    prog_varset::in, prog_varset::out, vartypes::in, vartypes::out) is det.
:- pred make_char_const_construction_alloc(char::in, maybe(string)::in,
    hlds_goal::out, prog_var::out,
    prog_varset::in, prog_varset::out, vartypes::in, vartypes::out) is det.
:- pred make_const_construction_alloc(cons_id::in, mer_type::in,
    maybe(string)::in, hlds_goal::out, prog_var::out,
    prog_varset::in, prog_varset::out, vartypes::in, vartypes::out) is det.

:- pred make_int_const_construction_alloc_in_proc(int::in,
    maybe(string)::in, hlds_goal::out, prog_var::out,
    proc_info::in, proc_info::out) is det.
:- pred make_string_const_construction_alloc_in_proc(string::in,
    maybe(string)::in, hlds_goal::out, prog_var::out,
    proc_info::in, proc_info::out) is det.
:- pred make_float_const_construction_alloc_in_proc(float::in,
    maybe(string)::in, hlds_goal::out, prog_var::out,
    proc_info::in, proc_info::out) is det.
:- pred make_char_const_construction_alloc_in_proc(char::in,
    maybe(string)::in, hlds_goal::out, prog_var::out,
    proc_info::in, proc_info::out) is det.
:- pred make_const_construction_alloc_in_proc(cons_id::in, mer_type::in,
    maybe(string)::in, hlds_goal::out, prog_var::out,
    proc_info::in, proc_info::out) is det.

    % Produce a goal to construct or deconstruct a unification with
    % a functor.  It fills in the non-locals, instmap_delta and
    % determinism fields of the goal_info.
    %
:- pred construct_functor(prog_var::in, cons_id::in, list(prog_var)::in,
    hlds_goal::out) is det.
:- pred deconstruct_functor(prog_var::in, cons_id::in, list(prog_var)::in,
    hlds_goal::out) is det.

    % Produce a goal to construct or deconstruct a tuple containing
    % the given list of arguments, filling in the non-locals,
    % instmap_delta and determinism fields of the goal_info.
    %
:- pred construct_tuple(prog_var::in, list(prog_var)::in, hlds_goal::out)
    is det.
:- pred deconstruct_tuple(prog_var::in, list(prog_var)::in, hlds_goal::out)
    is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module hlds.instmap.
:- import_module parse_tree.builtin_lib_types.
:- import_module parse_tree.prog_mode.
:- import_module parse_tree.set_of_var.

:- import_module pair.
:- import_module varset.

%-----------------------------------------------------------------------------%

true_goal = hlds_goal(true_goal_expr, GoalInfo) :-
    instmap_delta_init_reachable(InstMapDelta),
    goal_info_init(set_of_var.init, InstMapDelta, detism_det, purity_pure,
        GoalInfo).

true_goal_expr = conj(plain_conj, []).

true_goal_with_context(Context) = hlds_goal(GoalExpr, GoalInfo) :-
    hlds_goal(GoalExpr, GoalInfo0) = true_goal,
    goal_info_set_context(Context, GoalInfo0, GoalInfo).

fail_goal = hlds_goal(fail_goal_expr, GoalInfo) :-
    instmap_delta_init_unreachable(InstMapDelta),
    goal_info_init(set_of_var.init, InstMapDelta, detism_failure, purity_pure,
        GoalInfo).

fail_goal_expr = disj([]).

fail_goal_info = GoalInfo :-
    instmap_delta_init_unreachable(InstMapDelta),
    goal_info_init(set_of_var.init, InstMapDelta, detism_failure, purity_pure,
        GoalInfo).

fail_goal_with_context(Context) = hlds_goal(GoalExpr, GoalInfo) :-
    hlds_goal(GoalExpr, GoalInfo0) = fail_goal,
    goal_info_set_context(Context, GoalInfo0, GoalInfo).

%-----------------------------------------------------------------------------%

create_pure_atomic_complicated_unification(LHS, RHS, Context,
        UnifyMainContext, UnifySubContext, Goal) :-
    create_atomic_complicated_unification(LHS, RHS, Context,
        UnifyMainContext, UnifySubContext, purity_pure, Goal).

create_atomic_complicated_unification(LHS, RHS, Context,
        UnifyMainContext, UnifySubContext, Purity, Goal) :-
    UMode = ((free - free) -> (free - free)),
    Mode = ((free -> free) - (free -> free)),
    Unification = complicated_unify(UMode, can_fail, []),
    UnifyContext = unify_context(UnifyMainContext, UnifySubContext),
    goal_info_init(Context, GoalInfo0),
    goal_info_set_purity(Purity, GoalInfo0, GoalInfo),
    GoalExpr = unify(LHS, RHS, Mode, Unification, UnifyContext),
    Goal = hlds_goal(GoalExpr, GoalInfo).

%-----------------------------------------------------------------------------%

make_simple_assign(X, Y, UnifyMainContext, UnifySubContext, Goal) :-
    Ground = ground(shared, none),
    Mode = ((free -> Ground) - (Ground -> Ground)),
    Unification = assign(X, Y),
    UnifyContext = unify_context(UnifyMainContext, UnifySubContext),
    goal_info_init(set_of_var.list_to_set([X, Y]), instmap_delta_bind_var(X),
        detism_semi, purity_pure, GoalInfo),
    GoalExpr = unify(X, rhs_var(Y), Mode, Unification, UnifyContext),
    Goal = hlds_goal(GoalExpr, GoalInfo).

make_simple_test(X, Y, UnifyMainContext, UnifySubContext, Goal) :-
    Ground = ground(shared, none),
    Mode = ((Ground -> Ground) - (Ground -> Ground)),
    Unification = simple_test(X, Y),
    UnifyContext = unify_context(UnifyMainContext, UnifySubContext),
    goal_info_init(set_of_var.list_to_set([X, Y]), instmap_delta_bind_no_var,
        detism_semi, purity_pure, GoalInfo),
    GoalExpr = unify(X, rhs_var(Y), Mode, Unification, UnifyContext),
    Goal = hlds_goal(GoalExpr, GoalInfo).

%-----------------------------------------------------------------------------%

make_int_const_construction_alloc_in_proc(Int, MaybeName, Goal, Var,
        !ProcInfo) :-
    proc_info_create_var_from_type(int_type, MaybeName, Var, !ProcInfo),
    make_int_const_construction(Var, Int, Goal).

make_string_const_construction_alloc_in_proc(String, MaybeName, Goal, Var,
        !ProcInfo) :-
    proc_info_create_var_from_type(string_type, MaybeName, Var, !ProcInfo),
    make_string_const_construction(Var, String, Goal).

make_float_const_construction_alloc_in_proc(Float, MaybeName, Goal, Var,
        !ProcInfo) :-
    proc_info_create_var_from_type(float_type, MaybeName, Var, !ProcInfo),
    make_float_const_construction(Var, Float, Goal).

make_char_const_construction_alloc_in_proc(Char, MaybeName, Goal, Var,
        !ProcInfo) :-
    proc_info_create_var_from_type(char_type, MaybeName, Var, !ProcInfo),
    make_char_const_construction(Var, Char, Goal).

make_const_construction_alloc_in_proc(ConsId, Type, MaybeName, Goal, Var,
        !ProcInfo) :-
    proc_info_create_var_from_type(Type, MaybeName, Var, !ProcInfo),
    make_const_construction(Var, ConsId, Goal).

make_int_const_construction_alloc(Int, MaybeName, Goal, Var,
        !VarSet, !VarTypes) :-
    varset.new_maybe_named_var(MaybeName, Var, !VarSet),
    add_var_type(Var, int_type, !VarTypes),
    make_int_const_construction(Var, Int, Goal).

make_string_const_construction_alloc(String, MaybeName, Goal, Var,
        !VarSet, !VarTypes) :-
    varset.new_maybe_named_var(MaybeName, Var, !VarSet),
    add_var_type(Var, string_type, !VarTypes),
    make_string_const_construction(Var, String, Goal).

make_float_const_construction_alloc(Float, MaybeName, Goal, Var,
        !VarSet, !VarTypes) :-
    varset.new_maybe_named_var(MaybeName, Var, !VarSet),
    add_var_type(Var, float_type, !VarTypes),
    make_float_const_construction(Var, Float, Goal).

make_char_const_construction_alloc(Char, MaybeName, Goal, Var,
        !VarSet, !VarTypes) :-
    varset.new_maybe_named_var(MaybeName, Var, !VarSet),
    add_var_type(Var, char_type, !VarTypes),
    make_char_const_construction(Var, Char, Goal).

make_const_construction_alloc(ConsId, Type, MaybeName, Goal, Var,
        !VarSet, !VarTypes) :-
    varset.new_maybe_named_var(MaybeName, Var, !VarSet),
    add_var_type(Var, Type, !VarTypes),
    make_const_construction(Var, ConsId, Goal).

make_int_const_construction(Var, Int, Goal) :-
    make_const_construction(Var, int_const(Int), Goal).

make_string_const_construction(Var, String, Goal) :-
    make_const_construction(Var, string_const(String), Goal).

make_float_const_construction(Var, Float, Goal) :-
    make_const_construction(Var, float_const(Float), Goal).

make_char_const_construction(Var, Char, Goal) :-
    make_const_construction(Var, char_const(Char), Goal).

make_const_construction(Var, ConsId, hlds_goal(GoalExpr, GoalInfo)) :-
    RHS = rhs_functor(ConsId, is_not_exist_constr, []),
    Inst = bound(unique, inst_test_results_fgtc, [bound_functor(ConsId, [])]),
    Mode = (free -> Inst) - (Inst -> Inst),
    Unification = construct(Var, ConsId, [], [],
        construct_dynamically, cell_is_unique, no_construct_sub_info),
    Context = unify_context(umc_explicit, []),
    GoalExpr = unify(Var, RHS, Mode, Unification, Context),
    NonLocals = set_of_var.make_singleton(Var),
    instmap_delta_init_reachable(InstMapDelta0),
    instmap_delta_insert_var(Var, Inst, InstMapDelta0, InstMapDelta),
    goal_info_init(NonLocals, InstMapDelta, detism_det, purity_pure, GoalInfo).

construct_functor(Var, ConsId, Args, Goal) :-
    list.length(Args, Arity),
    RHS = rhs_functor(ConsId, is_not_exist_constr, Args),
    UnifyMode = (free_inst -> ground_inst) - (ground_inst -> ground_inst),
    UniMode = ((free_inst - ground_inst) -> (ground_inst - ground_inst)),
    list.duplicate(Arity, UniMode, UniModes),
    Unification = construct(Var, ConsId, Args, UniModes,
        construct_dynamically, cell_is_unique, no_construct_sub_info),
    UnifyContext = unify_context(umc_explicit, []),
    Unify = unify(Var, RHS, UnifyMode, Unification, UnifyContext),
    set_of_var.list_to_set([Var | Args], NonLocals),
    InstMapDelta = instmap_delta_bind_var(Var),
    goal_info_init(NonLocals, InstMapDelta, detism_det, purity_pure, GoalInfo),
    Goal = hlds_goal(Unify, GoalInfo).

deconstruct_functor(Var, ConsId, Args, Goal) :-
    list.length(Args, Arity),
    RHS = rhs_functor(ConsId, is_not_exist_constr, Args),
    UnifyMode = (ground_inst -> free_inst) - (ground_inst -> ground_inst),
    UniMode = ((ground_inst - free_inst) -> (ground_inst - ground_inst)),
    list.duplicate(Arity, UniMode, UniModes),
    UnifyContext = unify_context(umc_explicit, []),
    Unification = deconstruct(Var, ConsId, Args, UniModes, cannot_fail,
        cannot_cgc),
    Unify = unify(Var, RHS, UnifyMode, Unification, UnifyContext),
    set_of_var.list_to_set([Var | Args], NonLocals),
    InstMapDelta = instmap_delta_bind_vars(Args),
    goal_info_init(NonLocals, InstMapDelta, detism_det, purity_pure, GoalInfo),
    Goal = hlds_goal(Unify, GoalInfo).

construct_tuple(Tuple, Args, Goal) :-
    list.length(Args, Arity),
    ConsId = tuple_cons(Arity),
    construct_functor(Tuple, ConsId, Args, Goal).

deconstruct_tuple(Tuple, Args, Goal) :-
    list.length(Args, Arity),
    ConsId = tuple_cons(Arity),
    deconstruct_functor(Tuple, ConsId, Args, Goal).

%-----------------------------------------------------------------------------%
:- end_module hlds.make_goal.
%-----------------------------------------------------------------------------%
