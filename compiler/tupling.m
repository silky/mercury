%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 2005-2012 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: tupling.m.
% Author: wangp.
%
% This module takes the HLDS and performs a tupling transformation on the
% locally-defined procedures. That is, instead of passing all of the
% procedure's arguments separately, it will try to bundle some of them up and
% pass them together as a tuple.
%
% The idea is that some arguments passed to a procedure may not be needed
% immediately: between the start of the procedure and the first use of a
% given argument there may be a flush point, such as a call to another
% procedure. At these points, all values residing in registers that will be
% needed later in the procedure will need to be flushed to the stack, to be
% restored later. In some cases, it may be beneficial to refer to some
% arguments indirectly through a cell variable.  Flushing the (address of the)
% cell variable to the stack is enough to save all the field variables
% of the cell. The downside is that accessing a field variable requires
% going through a cell variable (the cost of which may be amortised if
% multiple field variables are needed in the same interval).
%
% Another potentially good reason to pass arguments in a tuple is if many
% procedures will be passing the same arguments to each other, e.g. as is
% often the case in mutually-recursive procedures.
%
% This implementation works as follows:
%
% 1. We divide the module into its constituent SCCs. We work our way
% through each SCC, starting from the bottommost SCC in the call graph.
%
% 2. For each SCC, we take guesses at a good tupling scheme for the
% procedures in the SCC, and count the average number of loads and stores
% between the registers and the stack for each given scheme.
%
% 3. If the best tupling scheme gives us an average number of loads/stores
% that compares favourably against the original (untupled) scheme, we go ahead
% and make the transformed versions of the procedures in the SCC and
% add them to the HLDS.
%
% 4. After all the SCCs have been processed, we update all calls to the
% original procedures to call their transformed versions instead.
%
% Step 2 in more detail:
%
% This implementation uses the names of input formal parameters to guess
% which values are common between the procedures in an SCC (for SCCs with
% more than one procedure). This means that if a variable name occurs as
% an input argument to more than one procedure in the SCC, those variables
% corresponding that name are candidates for tupling. In the interest of
% speeding up compilation times, the implementation only tries to tuple
% contiguous runs of the candidate variables. For example, if the candidates
% are [A,B,C,D], these combinations would be tested in turn, assuming a
% minimum run length of 3: {A,B,C,D}, {A,B,C}, and {B,C,D}.
%
% To count the average number of loads and stores in a procedure, we traverse
% the procedure's body, remembering which values are available in registers
% and the stack. When we reach a branch point, we use the relative frequencies
% that each branch was taken in a sample run to weight the costs incurred
% in each branch. The relative frequency data is gathered from the trace count
% summary file that must be provided by the user.
%
% Ideas for further work:
%
% - Smarter / more aggressive choosing of arguments to tuple
% - Inter-SCC analysis
% - Inter-module optimisation
% - Proper weighting of calls to procedures from within and without the SCC
%
% This transformation is similar in spirit to the transformation in
% stack_opt.m. It also shares much code with it.
%
% XXX We need to check that mprof can demangle the names of the transformed
% procedures correctly.
%
%-----------------------------------------------------------------------------%

:- module transform_hlds.tupling.
:- interface.

:- import_module hlds.hlds_module.

:- import_module io.

:- pred tuple_arguments(module_info::in, module_info::out, io::di, io::uo)
    is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module backend_libs.
:- import_module backend_libs.interval.
:- import_module check_hlds.mode_util.
:- import_module check_hlds.type_util.
:- import_module hlds.arg_info.
:- import_module hlds.goal_path.
:- import_module hlds.hlds_goal.
:- import_module hlds.hlds_llds.
:- import_module hlds.hlds_out.
:- import_module hlds.hlds_out.hlds_out_util.
:- import_module hlds.hlds_pred.
:- import_module hlds.hlds_rtti.
:- import_module hlds.make_goal.
:- import_module hlds.quantification.
:- import_module libs.compiler_util.
:- import_module libs.globals.
:- import_module libs.options.
:- import_module ll_backend.
:- import_module ll_backend.call_gen.
:- import_module ll_backend.live_vars.
:- import_module ll_backend.liveness.
:- import_module mdbcomp.
:- import_module mdbcomp.goal_path.
:- import_module mdbcomp.prim_data.
:- import_module mdbcomp.sym_name.
:- import_module mdbcomp.trace_counts.
:- import_module parse_tree.prog_data.
:- import_module parse_tree.prog_mode.
:- import_module parse_tree.prog_type.
:- import_module parse_tree.prog_util.
:- import_module parse_tree.set_of_var.
:- import_module transform_hlds.dependency_graph.

:- import_module array.
:- import_module assoc_list.
:- import_module bool.
:- import_module counter.
:- import_module digraph.
:- import_module float.
:- import_module int.
:- import_module list.
:- import_module map.
:- import_module maybe.
:- import_module multi_map.
:- import_module pair.
:- import_module require.
:- import_module set.
:- import_module string.
:- import_module term.
:- import_module unit.
:- import_module varset.

%-----------------------------------------------------------------------------%
%
% The top level.
%

tuple_arguments(!ModuleInfo, !IO) :-
    % XXX We should add a mechanism that would allow us to check whether
    % we have already read in this file, and if we have, then avoid reading
    % it in again.
    module_info_get_globals(!.ModuleInfo, Globals),
    globals.lookup_string_option(Globals, tuple_trace_counts_file,
        TraceCountsFile),
    ( TraceCountsFile = "" ->
        report_warning(Globals, "Warning: --tuple requires " ++
            "--tuple-trace-counts-file to work.\n", !IO)
    ;
        read_trace_counts_source(TraceCountsFile, Result, !IO),
        (
            Result = list_ok(_, TraceCounts),
            tuple_arguments_with_trace_counts(!ModuleInfo, TraceCounts)
        ;
            Result = list_error_message(Message),
            warn_trace_counts_error(Globals, TraceCountsFile, Message, !IO)
        )
    ).

:- pred warn_trace_counts_error(globals::in, string::in, string::in,
    io::di, io::uo) is det.

warn_trace_counts_error(Globals, TraceCountsFile, Reason, !IO) :-
    string.format(
        "Warning: unable to read trace count summary from %s (%s)\n",
        [s(TraceCountsFile), s(Reason)], Message),
    report_warning(Globals, Message, !IO).

:- pred tuple_arguments_with_trace_counts(module_info::in, module_info::out,
    trace_counts::in) is det.

tuple_arguments_with_trace_counts(!ModuleInfo, TraceCounts0) :-
    module_info_get_globals(!.ModuleInfo, Globals),
    % We use the same cost options as for the stack optimisation.
    globals.lookup_int_option(Globals,
        optimize_saved_vars_cell_cv_load_cost, CellVarLoadCost),
    globals.lookup_int_option(Globals,
        optimize_saved_vars_cell_cv_store_cost, CellVarStoreCost),
    globals.lookup_int_option(Globals,
        optimize_saved_vars_cell_fv_load_cost, FieldVarLoadCost),
    globals.lookup_int_option(Globals,
        optimize_saved_vars_cell_fv_store_cost, FieldVarStoreCost),
    globals.lookup_int_option(Globals, tuple_costs_ratio, CostsRatio),
    globals.lookup_int_option(Globals, tuple_min_args, MinArgsToTuple),
    % These are the costs for untupled variables.  We just assume it is
    % the lesser of the cell and field variable costs (usually the field
    % variable costs should be smaller).
    NormalVarStoreCost = min(CellVarStoreCost, FieldVarStoreCost),
    NormalVarLoadCost = min(CellVarLoadCost, FieldVarLoadCost),
    TuningParams = tuning_params(
        NormalVarLoadCost, NormalVarStoreCost,
        CellVarLoadCost, CellVarStoreCost,
        FieldVarLoadCost, FieldVarStoreCost,
        CostsRatio, MinArgsToTuple),

    module_info_get_name(!.ModuleInfo, ModuleName),
    restrict_trace_counts_to_module(ModuleName, TraceCounts0, TraceCounts),

    module_info_ensure_dependency_info(!ModuleInfo),
    module_info_dependency_info(!.ModuleInfo, DepInfo),
    hlds_dependency_info_get_dependency_graph(DepInfo, DepGraph),
    hlds_dependency_info_get_dependency_ordering(DepInfo, SCCs),

    % Add transformed versions of procedures that we think would be
    % beneficial.
    list.foldl3(maybe_tuple_scc(TraceCounts, TuningParams, DepGraph),
        SCCs, !ModuleInfo, counter.init(0), _, map.init, TransformMap),

    % Update the callers of the original procedures to call their
    % transformed versions instead. Do the same for the transformed
    % procedures themselves.
    list.foldl(fix_calls_in_procs(TransformMap), SCCs, !ModuleInfo),
    fix_calls_in_transformed_procs(TransformMap, !ModuleInfo).

%-----------------------------------------------------------------------------%

    % This predicate can be used in place of maybe_tuple_scc to evaluate
    % and transform each procedure of an SCC individually. This is to mimic
    % the behaviour from an earlier version of this file. It's currently
    % unused but might be useful for debugging.
    %
:- pred maybe_tuple_scc_individual_procs(trace_counts::in, tuning_params::in,
    dependency_graph::in, list(pred_proc_id)::in,
    module_info::in, module_info::out, counter::in, counter::out,
    transform_map::in, transform_map::out) is det.

maybe_tuple_scc_individual_procs(_TraceCounts, _TuningParams, _DepGraph,
        [], !ModuleInfo, !Counter, !TransformMap).
maybe_tuple_scc_individual_procs(TraceCounts, TuningParams, DepGraph,
        [Proc | Procs], !ModuleInfo, !Counter, !TransformMap) :-
    maybe_tuple_scc(TraceCounts, TuningParams, DepGraph,
        [Proc], !ModuleInfo, !Counter, !TransformMap),
    maybe_tuple_scc_individual_procs(TraceCounts, TuningParams, DepGraph,
        Procs, !ModuleInfo, !Counter, !TransformMap).

:- pred maybe_tuple_scc(trace_counts::in, tuning_params::in,
    dependency_graph::in, list(pred_proc_id)::in,
    module_info::in, module_info::out, counter::in, counter::out,
    transform_map::in, transform_map::out) is det.

maybe_tuple_scc(TraceCounts, TuningParams, DepGraph, SCC,
        !ModuleInfo, !Counter, !TransformMap) :-
    module_info_get_globals(!.ModuleInfo, Globals),
    globals.lookup_bool_option(Globals, very_verbose, VeryVerbose),
    (
        VeryVerbose = yes,
        trace [io(!IO)] (
            io.write_string("% Considering tupling in ", !IO),
            list.foldl(write_pred_proc_id(!.ModuleInfo), SCC, !IO),
            io.write_string("...\n", !IO)
        )
    ;
        VeryVerbose = no
    ),
    ( scc_has_local_callers(SCC, DepGraph) ->
        ( SCC = [SingleProc] ->
            candidate_headvars_of_proc(!.ModuleInfo, SingleProc,
                CandidateHeadVars)
        ;
            common_candidate_headvars_of_procs(!.ModuleInfo, SCC,
                CandidateHeadVars)
        ),
        MinArgsToTuple = TuningParams ^ tp_min_args_to_tuple,
        ( list.length(CandidateHeadVars) < MinArgsToTuple ->
            (
                VeryVerbose = yes,
                trace [io(!IO)] (
                    io.write_string("% Too few candidate headvars.\n", !IO)
                )
            ;
                VeryVerbose = no
            )
        ;
            maybe_tuple_scc_2(TraceCounts, TuningParams,
                SCC, CandidateHeadVars, !ModuleInfo,
                !Counter, !TransformMap, VeryVerbose)
        )
    ;
        % No need to work on this SCC if there are no callers to it
        % within this module.
        %
        % XXX: If part of the SCC is exported then we might want
        % to look at it, for intermodule tupling.
        (
            VeryVerbose = yes,
            trace [io(!IO)] (
                io.write_string("% SCC has no local callers.\n", !IO)
            )
        ;
            VeryVerbose = no
        )
    ).

:- pred scc_has_local_callers(list(pred_proc_id)::in, dependency_graph::in)
    is semidet.

scc_has_local_callers(CalleeProcs, DepGraph) :-
    some [CalleeProc] (
        list.member(CalleeProc, CalleeProcs),
        proc_has_local_callers(CalleeProc, DepGraph)
    ).

:- pred proc_has_local_callers(pred_proc_id::in, dependency_graph::in)
    is semidet.

proc_has_local_callers(CalleeProc, DepGraph) :-
    digraph.lookup_key(DepGraph, CalleeProc, CalleeKey),
    digraph.lookup_to(DepGraph, CalleeKey, CallingKeys),
    not set.empty(CallingKeys).

%-----------------------------------------------------------------------------%

:- pred maybe_tuple_scc_2(trace_counts::in, tuning_params::in,
    list(pred_proc_id)::in, candidate_headvars::in,
    module_info::in, module_info::out, counter::in, counter::out,
    transform_map::in, transform_map::out, bool::in) is det.

maybe_tuple_scc_2(TraceCounts, TuningParams, PredProcIds, CandidateHeadVars,
        !ModuleInfo, !Counter, !TransformMap, VeryVerbose) :-
    list.foldl2(prepare_proc_for_counting, PredProcIds,
        map.init, ReverseGoalPathMapMap, !ModuleInfo),
    % Count the average number of loads/stores without any transformation.
    count_load_stores_for_scc(TraceCounts, TuningParams, !.ModuleInfo,
        map.init, ReverseGoalPathMapMap, PredProcIds, CostsWithoutTupling),
    (
        VeryVerbose = yes,
        CostsWithoutTupling = costs(LoadsWoTupling, StoresWoTupling),
        trace [io(!IO)] (
            io.format("%% SCC costs without tupling = {%g, %g}\n",
                [f(LoadsWoTupling), f(StoresWoTupling)], !IO)
        )
    ;
        VeryVerbose = no
    ),
    ( CostsWithoutTupling = costs(0.0, 0.0) ->
        % Don't bother continuing.
        true
    ;
        maybe_tuple_scc_3(TraceCounts, TuningParams, ReverseGoalPathMapMap,
            PredProcIds, CandidateHeadVars, CostsWithoutTupling,
            !ModuleInfo, !Counter, !TransformMap, VeryVerbose)
    ).

:- pred maybe_tuple_scc_3(trace_counts::in, tuning_params::in,
    map(pred_proc_id, goal_reverse_path_map)::in, list(pred_proc_id)::in,
    candidate_headvars::in, costs::in, module_info::in, module_info::out,
    counter::in, counter::out, transform_map::in, transform_map::out,
    bool::in) is det.

maybe_tuple_scc_3(TraceCounts, TuningParams, ReverseGoalPathMapMap,
        PredProcIds, CandidateHeadVars, CostsWithoutTupling,
        !ModuleInfo, !Counter, !TransformMap, VeryVerbose) :-
    find_best_tupling_scheme(TraceCounts, TuningParams, !.ModuleInfo,
        ReverseGoalPathMapMap, PredProcIds, CandidateHeadVars,
        MaybeBestScheme),
    (
        MaybeBestScheme = no
    ;
        MaybeBestScheme = yes(CostsWithTupling-TuplingScheme),
        CostsWithTupling = costs(LoadsWithTupling, StoresWithTupling),
        (
            VeryVerbose = yes,
            trace [io(!IO)] (
                io.format("%% SCC costs with tupling = {%g, %g}\n",
                    [f(LoadsWithTupling), f(StoresWithTupling)], !IO)
            )
        ;
            VeryVerbose = no
        ),
        (
            should_use_tupling_scheme(TuningParams,
                CostsWithoutTupling, CostsWithTupling)
        ->
            (
                VeryVerbose = yes,
                trace [io(!IO)] (
                    io.print("% Proceeding with tupling\n", !IO)
                )
            ;
                VeryVerbose = no
            ),
            add_transformed_procs(TuplingScheme,
                !ModuleInfo, !Counter, !TransformMap)
        ;
            true
        )
    ).

:- pred should_use_tupling_scheme(tuning_params::in, costs::in, costs::in)
    is semidet.

should_use_tupling_scheme(TuningParams,
        costs(LoadsWithoutTupling, StoresWithoutTupling),
        costs(LoadsWithTupling, StoresWithTupling)) :-
    CostsRatio = float(TuningParams ^ tp_costs_ratio),
    TotalWithoutTupling = LoadsWithoutTupling + StoresWithoutTupling,
    TotalWithTupling = LoadsWithTupling + StoresWithTupling,
    ( TotalWithTupling = 0.0 ->
        TotalWithoutTupling > 0.0
    ;
        (TotalWithoutTupling * 100.0 / TotalWithTupling) >= CostsRatio
    ).

%-----------------------------------------------------------------------------%

:- type candidate_headvars == assoc_list(string, candidate_headvar_origins).

:- type candidate_headvar_origins == map(pred_proc_id, prog_var).

    % The "candidate headvars" of a procedure are the input arguments of
    % a procedure that we are considering to pass to the procedure as a
    % tuple.
    %
    % The "common" candidate headvars of an SCC (of more than one
    % procedure) are the input arguments that, when passed as a tuple, we
    % hope can be reused in calls to other procedures in the same SCC.
    % The heuristic used to find candidates is to look for input arguments
    % which have the same name in more than one procedure in the SCC.
    %
    % For each candidate, the name is put in an association list along
    % with a mappping to the actual variable within each procedure (if
    % that procedure has an input variable of the given name).  The order
    % of the elements in the association list is important later on,
    % since we only try tupling contiguous runs of the candidate variables.
    %
:- pred candidate_headvars_of_proc(module_info::in, pred_proc_id::in,
    candidate_headvars::out) is det.

candidate_headvars_of_proc(ModuleInfo, PredProcId @ proc(PredId, ProcId),
        CandidateHeadVars) :-
    module_info_pred_proc_info(ModuleInfo, PredId, ProcId, _, ProcInfo),
    proc_info_get_varset(ProcInfo, VarSet),
    proc_info_get_vartypes(ProcInfo, VarTypes),
    proc_info_get_headvars(ProcInfo, HeadVars),
    proc_info_get_argmodes(ProcInfo, ArgModes),
    CandidateHeadVars = list.filter_map_corresponding(
        candidate_headvars_of_proc_2(PredProcId, VarSet, VarTypes, ModuleInfo),
        HeadVars, ArgModes).

:- func candidate_headvars_of_proc_2(pred_proc_id, prog_varset, vartypes,
    module_info, prog_var, mer_mode)
    = pair(string, candidate_headvar_origins) is semidet.

candidate_headvars_of_proc_2(PredProcId, VarSet, VarTypes, ModuleInfo,
        HeadVar, ArgMode) = (Name - Origins) :-
    % We only tuple input arguments.
    mode_is_input(ModuleInfo, ArgMode),
    % Don't touch introduced typeinfo arguments.
    lookup_var_type(VarTypes, HeadVar, Type),
    not is_introduced_type_info_type(Type),
    varset.search_name(VarSet, HeadVar, Name),
    Origins = map.singleton(PredProcId, HeadVar).

:- pred common_candidate_headvars_of_procs(module_info::in,
    list(pred_proc_id)::in, candidate_headvars::out) is det.

common_candidate_headvars_of_procs(ModuleInfo, PredProcIds,
        CandidateHeadVars) :-
    list.map(candidate_headvars_of_proc(ModuleInfo),
        PredProcIds, ListsOfCandidates),
    list.condense(ListsOfCandidates, FlatListOfCandidates),
    multi_map.from_flat_assoc_list(FlatListOfCandidates, CandidatesMultiMap),
    map.foldl(common_candidate_headvars_of_procs_2, CandidatesMultiMap,
        [], CandidateHeadVars).

:- pred common_candidate_headvars_of_procs_2(
    string::in, list(candidate_headvar_origins)::in,
    candidate_headvars::in, candidate_headvars::out) is det.

common_candidate_headvars_of_procs_2(HeadVarName, ListOfOrigins,
        CandidateHeadVars0, CandidateHeadVars) :-
    % Only include this variable in the list of candidates if there are two
    % or more procedures in the SCC with head variables having the same name.
    ( ListOfOrigins = [_, _ | _] ->
        list.foldl(map.old_merge, ListOfOrigins, map.init, Origins),
        CandidateHeadVars = CandidateHeadVars0 ++ [HeadVarName - Origins]
    ;
        CandidateHeadVars = CandidateHeadVars0
    ).

%-----------------------------------------------------------------------------%

    % This is a mapping from the id of a procedure to the proposed
    % tupling that would be performed on the procedure's input arguments.
    %
:- type tupling_scheme == map(pred_proc_id, tupling_proposal).

:- type tupling_proposal
    --->    no_tupling
    ;       tupling(
                cell_var            :: prog_var,
                field_vars          :: list(prog_var),
                field_var_arg_pos   :: assoc_list(prog_var, int)
            ).

:- pred find_best_tupling_scheme(trace_counts::in, tuning_params::in,
    module_info::in, map(pred_proc_id, goal_reverse_path_map)::in,
    list(pred_proc_id)::in, candidate_headvars::in,
    maybe(pair(costs, tupling_scheme))::out) is det.

find_best_tupling_scheme(TraceCounts, TuningParams, ModuleInfo,
        ReverseGoalPathMapMap, PredProcIds, CandidateHeadVars,
        MaybeBestScheme) :-
    MinArgsToTuple = TuningParams ^ tp_min_args_to_tuple,
    fold_over_list_runs(
        find_best_tupling_scheme_2(TraceCounts, TuningParams,
            ModuleInfo, ReverseGoalPathMapMap, PredProcIds),
        CandidateHeadVars, MinArgsToTuple,
        no, MaybeBestScheme).

:- pred find_best_tupling_scheme_2(trace_counts::in, tuning_params::in,
    module_info::in, map(pred_proc_id, goal_reverse_path_map)::in,
    list(pred_proc_id)::in, candidate_headvars::in,
    maybe(pair(costs, tupling_scheme))::in,
    maybe(pair(costs, tupling_scheme))::out) is det.

find_best_tupling_scheme_2(TraceCounts, TuningParams, ModuleInfo,
        ReverseGoalPathMapMap, PredProcIds, CandidateHeadVars,
        MaybeBestScheme0, MaybeBestScheme) :-
    MinArgsToTuple = TuningParams ^ tp_min_args_to_tuple,
    list.map(
        make_tupling_proposal(ModuleInfo, CandidateHeadVars, MinArgsToTuple),
        PredProcIds, TuplingProposals),
    map.from_corresponding_lists(PredProcIds, TuplingProposals,
        TuplingScheme),
    count_load_stores_for_scc(TraceCounts, TuningParams, ModuleInfo,
        TuplingScheme, ReverseGoalPathMapMap, PredProcIds, Costs),
    (
        (
            MaybeBestScheme0 = no
        ;
            MaybeBestScheme0 = yes(PrevCosts - _),
            less_total_cost(Costs, PrevCosts)
        )
    ->
        MaybeBestScheme = yes(Costs - TuplingScheme)
    ;
        MaybeBestScheme = MaybeBestScheme0
    ).

:- pred make_tupling_proposal(module_info::in, candidate_headvars::in,
    int::in, pred_proc_id::in, tupling_proposal::out) is det.

make_tupling_proposal(ModuleInfo, CandidateHeadVars, MinArgsToTuple,
        PredProcId @ proc(PredId, ProcId), TuplingProposal) :-
    module_info_pred_proc_info(ModuleInfo, PredId, ProcId, _, ProcInfo),
    proc_info_get_varset(ProcInfo, VarSet),
    proc_info_get_headvars(ProcInfo, HeadVars),
    FieldVarArgPos = list.filter_map(
        (func(_ - Annotation) = (Var - Pos) is semidet :-
            map.search(Annotation, PredProcId, Var),
            list.nth_member_search(HeadVars, Var, Pos)),
        CandidateHeadVars),
    ( list.length(FieldVarArgPos) < MinArgsToTuple ->
        TuplingProposal = no_tupling
    ;
        % We need a new variable to act as the cell variable while
        % counting loads/stores for a proposed tupling, but we don't
        % add that variable to the varset permanently.
        varset.new_named_var("DummyCellVar", DummyCellVar, VarSet, _),
        FieldVars = assoc_list.keys(FieldVarArgPos),
        TuplingProposal = tupling(DummyCellVar, FieldVars, FieldVarArgPos)
    ).

:- pred less_total_cost(costs::in, costs::in) is semidet.

less_total_cost(costs(LoadsA, StoresA), costs(LoadsB, StoresB)) :-
    TotalA = LoadsA + StoresA,
    TotalB = LoadsB + StoresB,
    TotalA < TotalB.

%-----------------------------------------------------------------------------%

    % fold_over_list_runs(Pred, List, MinRunLength, !Acc):
    %
    % Call Pred for each consecutive run of elements in List of a length
    % greater or equal to MinRunLength, threading an accumulator through it.
    %
:- pred fold_over_list_runs(pred(list(L), A, A)::in(pred(in, in, out) is det),
    list(L)::in, int::in, A::in, A::out) is det.

fold_over_list_runs(_, [], _, !Acc).
fold_over_list_runs(Pred, List @ [_ | Tail], MinLength, !Acc) :-
    fold_over_list_runs_2(Pred, List, MinLength, !Acc),
    fold_over_list_runs(Pred, Tail, MinLength, !Acc).

:- pred fold_over_list_runs_2(
    pred(list(L), A, A)::in(pred(in, in, out) is det),
    list(L)::in, int::in, A::in, A::out) is det.

fold_over_list_runs_2(Pred, List, Length, !Acc) :-
    ( list.take(Length, List, Front) ->
        Pred(Front, !Acc),
        fold_over_list_runs_2(Pred, List, Length+1, !Acc)
    ;
        true
    ).

%-----------------------------------------------------------------------------%
%
% Transforming procedures.
%

:- pred add_transformed_procs(tupling_scheme::in, module_info::in,
    module_info::out, counter::in, counter::out, transform_map::in,
    transform_map::out) is det.

add_transformed_procs(TuplingScheme, !ModuleInfo, !Counter, !TransformMap) :-
    map.foldl3(add_transformed_proc, TuplingScheme,
        !ModuleInfo, !Counter, !TransformMap).

:- pred add_transformed_proc(pred_proc_id::in, tupling_proposal::in,
    module_info::in, module_info::out, counter::in, counter::out,
    transform_map::in, transform_map::out) is det.

add_transformed_proc(_, no_tupling, !ModuleInfo, !TransformMap, !Counter).
add_transformed_proc(PredProcId, tupling(_, FieldVars, _),
        !ModuleInfo, !Counter, !TransformMap) :-
    PredProcId = proc(PredId, ProcId),
    some [!ProcInfo] (
        module_info_pred_proc_info(!.ModuleInfo, PredId, ProcId,
            PredInfo, !:ProcInfo),

        % Build up information about intervals and which variables
        % are needed in each interval.
        build_interval_info(!.ModuleInfo, !.ProcInfo, IntervalInfo),

        % Create the cell variable.
        list.length(FieldVars, TupleArity),
        proc_info_get_vartypes(!.ProcInfo, VarTypes),
        lookup_var_types(VarTypes, FieldVars, TupleArgTypes),
        construct_type(type_ctor(unqualified("{}"), TupleArity), TupleArgTypes,
            TupleConsType),
        proc_info_create_var_from_type(TupleConsType,
            yes("TuplingCellVar"), CellVar, !ProcInfo),

        % Get the argument positions of the parameters to be tupled.
        proc_info_get_headvars(!.ProcInfo, HeadVars),
        list.map(nth_member_lookup(HeadVars), FieldVars, ArgsToTuple),

        % Build an insertion map of where the deconstruction
        % unifications are needed.
        build_insert_map(CellVar, FieldVars, IntervalInfo, InsertMap),

        % Make a transformed version of the procedure and add it to
        % the module.
        make_transformed_proc(CellVar, FieldVars, InsertMap, !ProcInfo),
        recompute_instmap_delta_proc(recompute_atomic_instmap_deltas,
            !ProcInfo, !ModuleInfo),
        counter.allocate(Num, !Counter),
        create_aux_pred(PredId, ProcId, PredInfo, !.ProcInfo, Num,
            AuxPredProcId, CallAux, !ModuleInfo),

        % Add an entry to the transform map for the new procedure.
        TransformedProc = transformed_proc(AuxPredProcId, TupleConsType,
            ArgsToTuple, CallAux),
        map.det_insert(PredProcId, TransformedProc, !TransformMap)
    ).

%-----------------------------------------------------------------------------%

:- pred make_transformed_proc(prog_var::in, list(prog_var)::in, insert_map::in,
    proc_info::in, proc_info::out) is det.

make_transformed_proc(CellVar, FieldVarsList, InsertMap, !ProcInfo) :-
    % Modify the procedure's formal parameters.
    proc_info_get_headvars(!.ProcInfo, HeadVars0),
    proc_info_get_argmodes(!.ProcInfo, ArgModes0),
    HeadVarsAndModes = list.filter_map_corresponding(
        (func(Var, Mode) = (Var - Mode) is semidet :-
            not list.member(Var, FieldVarsList)),
        HeadVars0, ArgModes0),
    assoc_list.keys_and_values(HeadVarsAndModes, HeadVars, ArgModes),
    proc_info_set_headvars(HeadVars ++ [CellVar], !ProcInfo),
    proc_info_set_argmodes(ArgModes ++ [in_mode], !ProcInfo),

    % Insert the necessary deconstruction unifications.
    proc_info_get_goal(!.ProcInfo, Goal0),
    proc_info_get_vartypes(!.ProcInfo, VarTypes0),
    proc_info_get_varset(!.ProcInfo, VarSet0),
    % XXX: I haven't checked if adding this feature has any effect.
    MaybeGoalFeature = yes(feature_tuple_opt),
    record_decisions_in_goal(Goal0, Goal1, VarSet0, VarSet1,
        VarTypes0, VarTypes1, map.init, RenameMapA, InsertMap,
        MaybeGoalFeature),

    % In some cases some of the field variables need to be available at
    % the very beginning of the procedure.  The required deconstructions
    % for those variables won't show up in the insert map.  To handle this
    % we just to insert a deconstruction unification at the start of the
    % procedure and let a simplification pass remove it later if not required.
    %
    % We could make build_insert_map add such required unifications to the
    % insert map, but record_decisions_in_goal would need to be modified
    % as well.
    %
    deconstruct_tuple(CellVar, FieldVarsList, ProcStartDeconstruct),
    ProcStartInsert = insert_spec(ProcStartDeconstruct,
        set_of_var.list_to_set(FieldVarsList)),
    insert_proc_start_deconstruction(Goal1, Goal2,
        VarSet1, VarSet, VarTypes1, VarTypes,
        RenameMapB, ProcStartInsert),
    rename_some_vars_in_goal(RenameMapB, Goal2, Goal3),

    map.old_merge(RenameMapA, RenameMapB, RenameMap),
    apply_headvar_correction(set_of_var.list_to_set(HeadVars), RenameMap,
        Goal3, Goal),
    proc_info_set_goal(Goal, !ProcInfo),
    proc_info_set_varset(VarSet, !ProcInfo),
    proc_info_set_vartypes(VarTypes, !ProcInfo),
    requantify_proc_general(ordinary_nonlocals_no_lambda, !ProcInfo).

:- pred insert_proc_start_deconstruction(hlds_goal::in, hlds_goal::out,
    prog_varset::in, prog_varset::out, vartypes::in, vartypes::out,
    rename_map::out, insert_spec::in) is det.

insert_proc_start_deconstruction(Goal0, Goal, !VarSet, !VarTypes,
        VarRename, Insert) :-
    % The tuple_opt feature is not used for this goal as we do want
    % other transformations to remove it if possible.
    make_inserted_goal(!VarSet, !VarTypes, map.init, VarRename,
        Insert, no, InsertGoal),
    Goal0 = hlds_goal(_, GoalInfo),
    conj_list_to_goal([InsertGoal, Goal0], GoalInfo, Goal).

%-----------------------------------------------------------------------------%

    % This predicate makes a new version of the given procedure in a module.
    % Amongst other things the new procedure is given a new pred_id and
    % proc_id, a new name and a new goal.
    %
    % CallAux is an output variable, which is unified with a goal that
    % can be used as a template for constructing calls to the newly
    % created procedure.
    %
    % See also create_aux_pred in loop_inv.m.
    %
:- pred create_aux_pred(pred_id::in, proc_id::in, pred_info::in,
    proc_info::in, int::in, pred_proc_id::out, hlds_goal::out,
    module_info::in, module_info::out) is det.

create_aux_pred(PredId, ProcId, PredInfo, ProcInfo, Counter,
        AuxPredProcId, CallAux, ModuleInfo0, ModuleInfo) :-
    proc_info_get_headvars(ProcInfo, AuxHeadVars),
    proc_info_get_goal(ProcInfo, Goal @ hlds_goal(_GoalExpr, GoalInfo)),
    proc_info_get_initial_instmap(ProcInfo, ModuleInfo0,
        InitialAuxInstMap),
    pred_info_get_typevarset(PredInfo, TVarSet),
    proc_info_get_vartypes(ProcInfo, VarTypes),
    pred_info_get_class_context(PredInfo, ClassContext),
    proc_info_get_rtti_varmaps(ProcInfo, RttiVarMaps),
    proc_info_get_varset(ProcInfo, VarSet),
    proc_info_get_inst_varset(ProcInfo, InstVarSet),
    pred_info_get_markers(PredInfo, Markers),
    pred_info_get_origin(PredInfo, OrigOrigin),
    proc_info_get_has_parallel_conj(ProcInfo, HasParallelConj),
    pred_info_get_var_name_remap(PredInfo, VarNameRemap),

    PredModule = pred_info_module(PredInfo),
    PredName = pred_info_name(PredInfo),
    PredOrFunc = pred_info_is_pred_or_func(PredInfo),
    Context = goal_info_get_context(GoalInfo),
    term.context_line(Context, Line),
    make_pred_name_with_context(PredModule, "tupling",
        PredOrFunc, PredName, Line, Counter, AuxPredSymName0),
    hlds_pred.proc_id_to_int(ProcId, ProcNo),
    Suffix = string.format("_%d", [i(ProcNo)]),
    add_sym_name_suffix(AuxPredSymName0, Suffix, AuxPredSymName),

    Origin = origin_transformed(transform_tuple(ProcNo), OrigOrigin, PredId),
    hlds_pred.define_new_pred(
        Origin,                 % in
        Goal,                   % in
        CallAux,                % out
        AuxHeadVars,            % in
        _ExtraArgs,             % out
        InitialAuxInstMap,      % in
        AuxPredSymName,         % in
        TVarSet,                % in
        VarTypes,               % in
        ClassContext,           % in
        RttiVarMaps,            % in
        VarSet,                 % in
        InstVarSet,             % in
        Markers,                % in
        address_is_not_taken,   % in
        HasParallelConj,        % in
        VarNameRemap,           % in
        ModuleInfo0,
        ModuleInfo,
        AuxPredProcId
    ).

%-----------------------------------------------------------------------------%
%
% Counting loads and stores between the stack and registers.
%

:- type count_info
    --->    count_info(
                ci_pred_proc_id             :: pred_proc_id,
                                            % Which procedure is being counted.
                ci_proc                     :: proc_info,
                ci_module                   :: module_info,
                ci_proc_counts              :: proc_trace_counts,
                ci_params                   :: tuning_params,
                ci_tupling_scheme           :: tupling_scheme,
                ci_rev_goal_path_map        :: goal_reverse_path_map
            ).

:- type tuning_params
    --->    tuning_params(
                tp_normal_var_load_cost     :: int,
                tp_normal_var_store_cost    :: int,
                tp_cell_var_load_cost       :: int,
                tp_cell_var_store_cost      :: int,
                tp_field_var_load_cost      :: int,
                tp_field_var_store_cost     :: int,
                tp_costs_ratio              :: int,
                tp_min_args_to_tuple        :: int
            ).

:- type count_state
    --->    count_state(
                cs_reg_vars             :: set_of_progvar,
                cs_stack_vars           :: set_of_progvar,
                cs_load_costs           :: float,
                cs_store_costs          :: float
            ).

:- type costs
    --->    costs(
                avg_loads               :: float,
                avg_stores              :: float
            ).

:- func get_tupling_proposal(count_info, pred_proc_id) = tupling_proposal
    is det.

get_tupling_proposal(CountInfo, PredProcId) = TuplingProposal :-
    ( map.search(CountInfo ^ ci_tupling_scheme, PredProcId, Probe) ->
        TuplingProposal = Probe
    ;
        TuplingProposal = no_tupling
    ).

:- func get_own_tupling_proposal(count_info) = tupling_proposal is det.

get_own_tupling_proposal(CountInfo) =
    get_tupling_proposal(CountInfo, CountInfo ^ ci_pred_proc_id).

%-----------------------------------------------------------------------------%

    % Collect all the information for a procedure that is required for
    % the count_load_stores_in_proc predicate to work.
    %
:- pred prepare_proc_for_counting(pred_proc_id::in,
    map(pred_proc_id, goal_reverse_path_map)::in,
    map(pred_proc_id, goal_reverse_path_map)::out,
    module_info::in, module_info::out) is det.

prepare_proc_for_counting(PredProcId, !ReverseGoalPathMapMap, !ModuleInfo) :-
    PredProcId = proc(PredId, ProcId),
    some [!ProcInfo] (
        module_info_pred_proc_info(!.ModuleInfo, PredId, ProcId,
            PredInfo, !:ProcInfo),
        pred_info_get_markers(PredInfo, Markers),
        pred_info_get_arg_types(PredInfo, ArgTypes),
        generate_proc_arg_info(Markers, ArgTypes, !.ModuleInfo, !ProcInfo),

        detect_liveness_proc(!.ModuleInfo, PredProcId, !ProcInfo),
        initial_liveness(!.ProcInfo, PredId, !.ModuleInfo, Liveness0),
        module_info_get_globals(!.ModuleInfo, Globals),
        body_should_use_typeinfo_liveness(PredInfo, Globals, TypeInfoLiveness),
        globals.lookup_bool_option(Globals,
            opt_no_return_calls, OptNoReturnCalls),
        array.init(1, is_not_dummy_type, DummyDummyTypeArray),
        AllocData = alloc_data(!.ModuleInfo, !.ProcInfo, PredProcId,
            TypeInfoLiveness, OptNoReturnCalls, DummyDummyTypeArray),
        fill_goal_id_slots_in_proc(!.ModuleInfo, ContainingGoalMap, !ProcInfo),
        ReverseGoalPathMap = create_reverse_goal_path_map(ContainingGoalMap),
        map.det_insert(PredProcId, ReverseGoalPathMap,
            !ReverseGoalPathMapMap),
        proc_info_get_goal(!.ProcInfo, Goal0),
        OptTupleAlloc0 = opt_tuple_alloc,
        FailVars = set_of_var.init,
        NondetLiveness0 = set_of_var.init,
        build_live_sets_in_goal_no_par_stack(Goal0, Goal, FailVars, AllocData,
            OptTupleAlloc0, _OptTupleAlloc, Liveness0, _Liveness,
            NondetLiveness0, _NondetLiveness),
        proc_info_set_goal(Goal, !ProcInfo),

        module_info_set_pred_proc_info(PredId, ProcId, PredInfo, !.ProcInfo,
            !ModuleInfo)
    ).

%-----------------------------------------------------------------------------%

% The opt_tuple_alloc structure is constructed by live_vars.m. As far as I can
% tell we don't need such a thing for this module so we just define some stubs.

:- type opt_tuple_alloc
    --->    opt_tuple_alloc.

:- instance stack_alloc_info(opt_tuple_alloc) where [
    pred(at_call_site/4) is opt_at_call_site,
    pred(at_resume_site/4) is opt_at_resume_site,
    pred(at_par_conj/4) is opt_at_par_conj,
    pred(at_recursive_call_for_loop_control/4) is
        opt_at_recursive_call_for_loop_control
].

:- pred opt_at_call_site(need_across_call::in, alloc_data::in,
    opt_tuple_alloc::in, opt_tuple_alloc::out) is det.

opt_at_call_site(_NeedAtCall, _AllocData, !StackAlloc).

:- pred opt_at_resume_site(need_in_resume::in, alloc_data::in,
    opt_tuple_alloc::in, opt_tuple_alloc::out) is det.

opt_at_resume_site(_NeedAtResume, _AllocData, !StackAlloc).

:- pred opt_at_par_conj(need_in_par_conj::in, alloc_data::in,
    opt_tuple_alloc::in, opt_tuple_alloc::out) is det.

opt_at_par_conj(_NeedParConj, _AllocData, !StackAlloc).

:- pred opt_at_recursive_call_for_loop_control(need_for_loop_control::in,
    alloc_data::in, opt_tuple_alloc::in, opt_tuple_alloc::out) is det.

opt_at_recursive_call_for_loop_control(_NeedLC, _AllocData, !StackAlloc).

%-----------------------------------------------------------------------------%

:- pred count_load_stores_for_scc(trace_counts::in, tuning_params::in,
    module_info::in, tupling_scheme::in,
    map(pred_proc_id, goal_reverse_path_map)::in,
    list(pred_proc_id)::in, costs::out) is det.

count_load_stores_for_scc(TraceCounts, TuningParams, ModuleInfo,
        TuplingScheme, ReverseGoalPathMapMap, PredProcIds, Costs) :-
    list.foldl2(
        count_load_stores_for_scc_2(TraceCounts, TuningParams, ModuleInfo,
            TuplingScheme, ReverseGoalPathMapMap),
        PredProcIds, 0.0, Loads, 0.0, Stores),
    Costs = costs(Loads, Stores).

:- pred count_load_stores_for_scc_2(trace_counts::in, tuning_params::in,
    module_info::in, tupling_scheme::in,
    map(pred_proc_id, goal_reverse_path_map)::in,
    pred_proc_id::in, float::in, float::out, float::in, float::out) is det.

count_load_stores_for_scc_2(TraceCounts, TuningParams, ModuleInfo,
        TuplingScheme, ReverseGoalPathMapMap, PredProcId, !Loads, !Stores) :-
    PredProcId = proc(PredId, ProcId),
    module_info_pred_proc_info(ModuleInfo, PredId, ProcId,
        PredInfo, ProcInfo),
    % XXX: Different declaring vs defining modules not handled.
    ProcLabel = ordinary_proc_label(pred_info_module(PredInfo),
        pred_info_is_pred_or_func(PredInfo),
        pred_info_module(PredInfo),
        pred_info_name(PredInfo),
        pred_info_orig_arity(PredInfo),
        proc_id_to_int(ProcId)),
    pred_info_get_context(PredInfo, Context),
    Context = context(FileName, _),
    ProcLabelInContext = proc_label_in_context(pred_info_module(PredInfo),
        FileName, ProcLabel),
    ( get_proc_counts(TraceCounts, ProcLabelInContext, yes(ProcCounts)) ->
        map.lookup(ReverseGoalPathMapMap, PredProcId, ReverseGoalPathMap),
        CountInfo = count_info(PredProcId, ProcInfo, ModuleInfo, ProcCounts,
            TuningParams, TuplingScheme, ReverseGoalPathMap),
        count_load_stores_in_proc(CountInfo, ProcLoads, ProcStores),
        % XXX: There is a problem somewhere causing CALL and EXIT
        % events not to show up for some procedures in trace count files.
        % The weighting of the procedure's costs is disabled.
        % However, if working, it still wouldn't be ideal as we don't
        % know how many of the calls to the procedure came from within
        % or without the SCC.
        % get_proc_calls(ProcCounts, Weight),
        Weight = 1,
        !:Loads = !.Loads + float(Weight) * ProcLoads,
        !:Stores = !.Stores + float(Weight) * ProcStores
    ;
        true
    ).

%-----------------------------------------------------------------------------%

:- pred count_load_stores_in_proc(count_info::in, float::out, float::out)
    is det.

count_load_stores_in_proc(CountInfo, Loads, Stores) :-
    proc(PredId, _) = CountInfo ^ ci_pred_proc_id,
    ProcInfo = CountInfo ^ ci_proc,
    ModuleInfo = CountInfo ^ ci_module,
    initial_liveness(ProcInfo, PredId, ModuleInfo, InitialLiveness),
    CountState0 = count_state(InitialLiveness, set_of_var.init, 0.0, 0.0),
    proc_info_get_goal(ProcInfo, Goal),
    count_load_stores_in_goal(Goal, CountInfo, CountState0, CountState1),
    arg_info.partition_proc_args(ProcInfo, ModuleInfo, _, OutputArgs, _),
    cls_require_in_regs(CountInfo, set.to_sorted_list(OutputArgs),
        CountState1, CountState),
    CountState = count_state(_, _, Loads, Stores).

%-----------------------------------------------------------------------------%

    % This code is based on interval.build_interval_info_in_goal.
    %
:- pred count_load_stores_in_goal(hlds_goal::in, count_info::in,
    count_state::in, count_state::out) is det.

count_load_stores_in_goal(Goal, CountInfo, !CountState) :-
    Goal = hlds_goal(GoalExpr, GoalInfo),
    (
        GoalExpr = unify(_, _, _, Unification, _),
        (
            Unification = construct(CellVar, _ConsId, ArgVars, _ArgModes,
                _HowToConstruct, _, _),
            cls_require_in_regs(CountInfo, ArgVars, !CountState),
            cls_put_in_regs([CellVar], !CountState)
        ;
            Unification = deconstruct(CellVar, _ConsId, ArgVars, _ArgModes,
                _, _),
            cls_put_in_regs_via_deconstruct(CountInfo, CellVar, ArgVars,
                !CountState)
        ;
            Unification = assign(ToVar, FromVar),
            cls_require_in_reg(CountInfo, FromVar, !CountState),
            cls_put_in_regs([ToVar], !CountState)
        ;
            Unification = simple_test(Var1, Var2),
            cls_require_in_regs(CountInfo, [Var1, Var2], !CountState)
        ;
            Unification = complicated_unify(_, _, _),
            unexpected($module, $pred, "complicated_unify")
        )
    ;
        GoalExpr = plain_call(PredId, ProcId, _, Builtin, _, _),
        (
            Builtin = not_builtin,
            TuplingProposal = get_tupling_proposal(CountInfo,
                proc(PredId, ProcId)),
            TuplingProposal = tupling(_, _, _)
        ->
            count_load_stores_in_call_to_tupled(GoalExpr, GoalInfo,
                CountInfo, TuplingProposal, !CountState)
        ;
            count_load_stores_in_call_to_not_tupled(GoalExpr, GoalInfo,
                CountInfo, !CountState)
        )
    ;
        GoalExpr = generic_call(GenericCall, ArgVars, ArgModes, MaybeArgRegs,
            _Detism),
        ProcInfo = CountInfo ^ ci_proc,
        ModuleInfo = CountInfo ^ ci_module,
        goal_info_get_maybe_need_across_call(GoalInfo, MaybeNeedAcrossCall),
        proc_info_get_vartypes(ProcInfo, VarTypes),
        lookup_var_types(VarTypes, ArgVars, ArgTypes),
        arg_info.generic_call_arg_reg_types(ModuleInfo, VarTypes,
            GenericCall, ArgVars, MaybeArgRegs, ArgRegTypes),
        arg_info.compute_in_and_out_vars_sep_regs(ModuleInfo, ArgVars,
            ArgModes, ArgTypes, ArgRegTypes, InputArgsR, InputArgsF,
            OutputArgsR, OutputArgsF),
        InputArgs = InputArgsR ++ InputArgsF,
        OutputArgs = OutputArgsR ++ OutputArgsF,

        (
            ( GenericCall = higher_order(_, _, _, _)
            ; GenericCall = class_method(_, _, _, _)
            ; GenericCall = event_call(_)
            ),
            module_info_get_globals(ModuleInfo, Globals),
            call_gen.generic_call_info(Globals, GenericCall,
                length(InputArgsR), length(InputArgsF), _,
                GenericVarsArgInfos, _, _),
            assoc_list.keys(GenericVarsArgInfos, GenericVars),
            list.append(GenericVars, InputArgs, Inputs),
            Outputs = set.list_to_set(OutputArgs),
            count_load_stores_for_call(CountInfo, Inputs, Outputs,
                MaybeNeedAcrossCall, GoalInfo, !CountState)
        ;
            GenericCall = cast(_),
            % Casts are generated inline.
            cls_require_in_regs(CountInfo, InputArgs, !CountState),
            cls_put_in_regs(OutputArgs, !CountState)
        )
    ;
        GoalExpr = call_foreign_proc(_Attributes, PredId, ProcId,
            Args, ExtraArgs, _MaybeTraceRuntimeCond, _PragmaCode),
        ModuleInfo = CountInfo ^ ci_module,
        module_info_pred_proc_info(ModuleInfo, PredId, ProcId,
            _PredInfo, ProcInfo),
        ArgVars = list.map(foreign_arg_var, Args),
        ExtraVars = list.map(foreign_arg_var, ExtraArgs),
        CallingProcInfo = CountInfo ^ ci_proc,
        proc_info_get_vartypes(CallingProcInfo, VarTypes),
        arg_info.partition_proc_call_args(ProcInfo, VarTypes,
            ModuleInfo, ArgVars, InputArgVarSet, OutputArgVarSet, _),
        set.to_sorted_list(InputArgVarSet, InputArgVars),
        list.append(InputArgVars, ExtraVars, InputVars),
        (
            goal_info_maybe_get_maybe_need_across_call(GoalInfo,
                MaybeNeedAcrossCall),
            MaybeNeedAcrossCall = yes(_)
        ->
            count_load_stores_for_call(CountInfo, InputVars, OutputArgVarSet,
                MaybeNeedAcrossCall, GoalInfo, !CountState)
        ;
            cls_require_in_regs(CountInfo, InputVars, !CountState),
            cls_clobber_regs(OutputArgVarSet, !CountState)
        )
    ;
        GoalExpr = scope(Reason, SubGoal),
        ( Reason = from_ground_term(_, from_ground_term_construct) ->
            % There are no loads or stored in these scopes.
            true
        ;
            count_load_stores_in_goal(SubGoal, CountInfo, !CountState)
        )
    ;
        GoalExpr = conj(ConjType, Goals),
        (
            ConjType = plain_conj,
            count_load_stores_in_conj(Goals, CountInfo, !CountState)
        ;
            ConjType = parallel_conj,
            sorry($module, $pred, "tupling with parallel conjunctions")
        )
    ;
        GoalExpr = disj(Goals),
        count_load_stores_in_disj(Goals, CountInfo, !CountState)
    ;
        GoalExpr = switch(_Var, _Det, Cases),
        count_load_stores_in_cases(Cases, CountInfo, !CountState)
    ;
        GoalExpr = negation(SubGoal),
        goal_info_get_resume_point(SubGoal ^ hlds_goal_info, ResumePoint),
        (
            ResumePoint = resume_point(LiveVars, _ResumeLocs),
            cls_require_flushed(CountInfo, LiveVars, !CountState)
        ;
            ResumePoint = no_resume_point,
            unexpected($module, $pred, "no_resume_point for not")
        ),
        count_load_stores_in_goal(SubGoal, CountInfo, !CountState)
    ;
        GoalExpr = if_then_else(_, Cond, Then, Else),
        goal_info_get_resume_point(Cond ^ hlds_goal_info, ResumePoint),
        (
            ResumePoint = resume_point(LiveVars, _ResumeLocs),
            cls_require_flushed(CountInfo, LiveVars, !CountState),
            count_load_stores_in_goal(Cond, CountInfo, !CountState),

            reset_count_state_counts(!.CountState, ResetCountInfo),
            count_load_stores_in_goal(Then, CountInfo,
                ResetCountInfo, ThenCountInfo),
            count_load_stores_in_goal(Else, CountInfo,
                ResetCountInfo, ElseCountInfo),

            ProcCounts = CountInfo ^ ci_proc_counts,
            ThenGoalId = goal_info_get_goal_id(Then ^ hlds_goal_info),
            ElseGoalId = goal_info_get_goal_id(Else ^ hlds_goal_info),
            get_ite_relative_frequencies(ProcCounts,
                CountInfo ^ ci_rev_goal_path_map,
                ThenGoalId, ElseGoalId, ThenRelFreq, ElseRelFreq),

            add_branch_costs(ThenCountInfo, ThenRelFreq, !CountState),
            add_branch_costs(ElseCountInfo, ElseRelFreq, !CountState)
        ;
            ResumePoint = no_resume_point,
            unexpected($module, $pred, "no_resume_point for if_then_else")
        )
    ;
        GoalExpr = shorthand(_),
        % These should have been expanded out by now.
        unexpected($module, $pred, "shorthand")
    ).

%-----------------------------------------------------------------------------%

:- pred count_load_stores_in_call_to_tupled(
    hlds_goal_expr::in(goal_expr_plain_call),
    hlds_goal_info::in, count_info::in,
    tupling_proposal::in(bound(tupling(ground, ground, ground))),
    count_state::in, count_state::out) is det.

count_load_stores_in_call_to_tupled(GoalExpr, GoalInfo, CountInfo,
        CalleeTuplingProposal, !CountState) :-
    GoalExpr = plain_call(CalleePredId, CalleeProcId, ArgVars, _, _, _),
    CalleeTuplingProposal = tupling(CellVar, FieldVars, FieldVarArgPos),
    ModuleInfo = CountInfo ^ ci_module,
    module_info_pred_proc_info(ModuleInfo, CalleePredId, CalleeProcId,
        _, CalleeProcInfo),
    CallingProcInfo = CountInfo ^ ci_proc,
    proc_info_get_vartypes(CallingProcInfo, VarTypes),
    arg_info.partition_proc_call_args(CalleeProcInfo, VarTypes,
        ModuleInfo, ArgVars, InputArgs0, Outputs, _),
    (
        % If the caller is a tupled procedure, and every field variable
        % of the tuple appears as an input argument to the callee AND
        % every such argument is in a position matching the field variable's
        % position in the tupling proposal, then the cell var of the caller
        % can be reused as the call var for the callee.
        %
        % TODO: If we kept track of the aliases of field variables,
        % then they could be checked also.
        get_own_tupling_proposal(CountInfo) = tupling(_, _, _),
        all [Var] (
            list.member(Var, FieldVars)
        => (
            set.member(Var, InputArgs0),
            assoc_list.search(FieldVarArgPos, Var, Pos),
            list.nth_member_search(ArgVars, Var, Pos)
        ))
    ->
        % In this case, the cell var is not being used to access field
        % variables, so it should not incur the cell var cost.
        cls_require_normal_var_in_reg(CountInfo, CellVar, !CountState),
        set.delete_list(FieldVars, InputArgs0, InputArgs)
    ;
        % The cell var cannot be used for the callee, so we must add
        % the cost of constructing a new tuple.
        TuplingParams = CountInfo ^ ci_params,
        CellVarStoreCost = float(TuplingParams ^ tp_cell_var_store_cost),
        !CountState ^ cs_store_costs :=
            !.CountState ^ cs_store_costs + CellVarStoreCost,
        InputArgs = InputArgs0
    ),
    set.to_sorted_list(InputArgs, Inputs),
    goal_info_get_maybe_need_across_call(GoalInfo, MaybeNeedAcrossCall),
    count_load_stores_for_call(CountInfo, Inputs, Outputs,
        MaybeNeedAcrossCall, GoalInfo, !CountState).

:- pred count_load_stores_in_call_to_not_tupled(
    hlds_goal_expr::in(goal_expr_plain_call),
    hlds_goal_info::in, count_info::in, count_state::in, count_state::out)
    is det.

count_load_stores_in_call_to_not_tupled(GoalExpr, GoalInfo, CountInfo,
        !CountState) :-
    GoalExpr = plain_call(PredId, ProcId, ArgVars, Builtin, _, _),
    ModuleInfo = CountInfo ^ ci_module,
    module_info_pred_proc_info(ModuleInfo, PredId, ProcId,
        _PredInfo, CalleeProcInfo),
    ProcInfo = CountInfo ^ ci_proc,
    proc_info_get_vartypes(ProcInfo, VarTypes),
    arg_info.partition_proc_call_args(CalleeProcInfo, VarTypes,
        ModuleInfo, ArgVars, InputArgs, OutputArgs, _),
    set.to_sorted_list(InputArgs, Inputs),
    set.to_sorted_list(OutputArgs, Outputs),
    (
        Builtin = inline_builtin,
        cls_require_in_regs(CountInfo, Inputs, !CountState),
        cls_put_in_regs(Outputs, !CountState)
    ;
        ( Builtin = out_of_line_builtin
        ; Builtin = not_builtin
        ),
        goal_info_get_maybe_need_across_call(GoalInfo, MaybeNeedAcrossCall),
        count_load_stores_for_call(CountInfo, Inputs, OutputArgs,
            MaybeNeedAcrossCall, GoalInfo, !CountState)
    ).

:- pred count_load_stores_for_call(count_info::in, list(prog_var)::in,
    set(prog_var)::in, maybe(need_across_call)::in,
    hlds_goal_info::in, count_state::in, count_state::out) is det.

count_load_stores_for_call(CountInfo, Inputs, Outputs, MaybeNeedAcrossCall,
        _GoalInfo, !CountState) :-
    cls_require_in_regs(CountInfo, Inputs, !CountState),
    (
        MaybeNeedAcrossCall = yes(NeedAcrossCall),
        NeedAcrossCall = need_across_call(ForwardVars,
            ResumeVars, NondetLiveVars),
        AllVars = set_of_var.union_list(
            [ForwardVars, ResumeVars, NondetLiveVars]),
        cls_require_flushed(CountInfo, AllVars, !CountState),
        cls_clobber_regs(Outputs, !CountState)
    ;
        MaybeNeedAcrossCall = no,
        unexpected($module, $pred, "no need across call")
    ).

%-----------------------------------------------------------------------------%

:- pred count_load_stores_in_conj(hlds_goals::in, count_info::in,
    count_state::in, count_state::out) is det.

count_load_stores_in_conj([], _CountInfo, !CountState).
count_load_stores_in_conj([Goal | Goals], CountInfo, !CountState) :-
    count_load_stores_in_goal(Goal, CountInfo, !CountState),
    count_load_stores_in_conj(Goals, CountInfo, !CountState).

:- pred count_load_stores_in_disj(hlds_goals::in, count_info::in,
    count_state::in, count_state::out) is det.

count_load_stores_in_disj([], _CountInfo, !CountState).
count_load_stores_in_disj([Goal | Goals], CountInfo, !CountState) :-
    GoalInfo = Goal ^ hlds_goal_info,
    goal_info_get_resume_point(GoalInfo, ResumePoint),
    (
        ResumePoint = resume_point(LiveVars, _ResumeLocs),
        cls_require_flushed(CountInfo, LiveVars, !CountState)
    ;
        ResumePoint = no_resume_point
    ),
    reset_count_state_counts(!.CountState, BranchCountState0),
    count_load_stores_in_goal(Goal, CountInfo,
        BranchCountState0, BranchCountState),
    ProcCounts = CountInfo ^ ci_proc_counts,
    GoalId = goal_info_get_goal_id(GoalInfo),
    get_disjunct_relative_frequency(ProcCounts,
        CountInfo ^ ci_rev_goal_path_map, GoalId, RelFreq),
    add_branch_costs(BranchCountState, RelFreq, !CountState),
    count_load_stores_in_disj(Goals, CountInfo, !CountState).

:- pred count_load_stores_in_cases(list(case)::in, count_info::in,
    count_state::in, count_state::out) is det.

count_load_stores_in_cases([], _CountInfo, !CountState).
count_load_stores_in_cases([Case | Cases], CountInfo, !CountState) :-
    Case = case(_MainConsId, _OtherConsIds, Goal),
    GoalInfo = Goal ^ hlds_goal_info,
    goal_info_get_resume_point(GoalInfo, ResumePoint),
    (
        ResumePoint = resume_point(LiveVars, _ResumeLocs),
        cls_require_flushed(CountInfo, LiveVars, !CountState)
    ;
        ResumePoint = no_resume_point
    ),
    reset_count_state_counts(!.CountState, BranchCountState0),
    count_load_stores_in_goal(Goal, CountInfo, BranchCountState0,
        BranchCountState),
    ProcCounts = CountInfo ^ ci_proc_counts,
    GoalId = goal_info_get_goal_id(GoalInfo),
    get_case_relative_frequency(ProcCounts,
        CountInfo ^ ci_rev_goal_path_map, GoalId, RelFreq),
    add_branch_costs(BranchCountState, RelFreq, !CountState),
    count_load_stores_in_cases(Cases, CountInfo, !CountState).

%-----------------------------------------------------------------------------%

    % Make the values of the given variables available in registers.
    %
:- pred cls_require_in_regs(count_info::in, list(prog_var)::in,
    count_state::in, count_state::out) is det.

cls_require_in_regs(CountInfo, Vars, !CountState) :-
    list.foldl(cls_require_in_reg(CountInfo), Vars, !CountState).

:- pred cls_require_in_reg(count_info::in, prog_var::in, count_state::in,
    count_state::out) is det.

cls_require_in_reg(CountInfo, Var, !CountState) :-
    (
        TuplingProposal = get_own_tupling_proposal(CountInfo),
        TuplingProposal = tupling(_, FieldVars, _),
        list.member(Var, FieldVars)
    ->
        cls_require_field_var_in_reg(CountInfo, TuplingProposal,
            Var, !CountState)
    ;
        cls_require_normal_var_in_reg(CountInfo, Var, !CountState)
    ).

:- pred cls_require_normal_var_in_reg(count_info::in, prog_var::in,
    count_state::in, count_state::out) is det.

cls_require_normal_var_in_reg(CountInfo, Var, !CountState) :-
    TuningParams = CountInfo ^ ci_params,
    NormalLoadCost = TuningParams ^ tp_normal_var_load_cost,
    cls_require_var_in_reg_with_cost(NormalLoadCost, Var, !CountState).

:- pred cls_require_field_var_in_reg(count_info::in,
    tupling_proposal::in(bound(tupling(ground, ground, ground))),
    prog_var::in, count_state::in, count_state::out) is det.

cls_require_field_var_in_reg(CountInfo, TuplingProposal, FieldVar,
        CountState0, CountState) :-
    CountState0 = count_state(RegVars0, StackVars, Loads0, Stores),
    ( set_of_var.member(RegVars0, FieldVar) ->
        CountState = CountState0
    ;
        TuplingProposal = tupling(CellVar, _, _),
        TuningParams = CountInfo ^ ci_params,
        CvLoadCost = float(TuningParams ^ tp_cell_var_load_cost),
        FvLoadCost = float(TuningParams ^ tp_field_var_load_cost),
        ( set_of_var.member(RegVars0, CellVar) ->
            set_of_var.insert(FieldVar, RegVars0, RegVars),
            Loads = Loads0 + FvLoadCost
        ;
            set_of_var.insert_list([CellVar, FieldVar], RegVars0, RegVars),
            Loads = Loads0 + CvLoadCost + FvLoadCost
        ),
        CountState = count_state(RegVars, StackVars, Loads, Stores)
    ).

:- pred cls_require_var_in_reg_with_cost(int::in, prog_var::in,
    count_state::in, count_state::out) is det.

cls_require_var_in_reg_with_cost(LoadCost, Var, CountState0, CountState) :-
    CountState0 = count_state(RegVars0, StackVars, Loads0, Stores),
    ( set_of_var.member(RegVars0, Var) ->
        CountState = CountState0
    ;
        set_of_var.insert(Var, RegVars0, RegVars),
        Loads = Loads0 + float(LoadCost),
        CountState = count_state(RegVars, StackVars, Loads, Stores)
    ).

    % Put the values of the given variables into registers.
    %
:- pred cls_put_in_regs(list(prog_var)::in, count_state::in, count_state::out)
    is det.

cls_put_in_regs(Vars, !CountState) :-
    RegVars0 = !.CountState ^ cs_reg_vars,
    set_of_var.insert_list(Vars, RegVars0, RegVars),
    !CountState ^ cs_reg_vars := RegVars.

:- pred cls_put_in_regs_via_deconstruct(count_info::in, prog_var::in,
    list(prog_var)::in, count_state::in, count_state::out) is det.

cls_put_in_regs_via_deconstruct(CountInfo,
        DeconstructCellVar, DeconstructFieldVars, !State) :-
    TuningParams = CountInfo ^ ci_params,
    CvLoadCost = TuningParams ^ tp_cell_var_load_cost,
    FvLoadCost = TuningParams ^ tp_field_var_load_cost,
    TuplingProposal = get_own_tupling_proposal(CountInfo),
    (
        TuplingProposal = no_tupling,
        cls_require_var_in_reg_with_cost(CvLoadCost,
            DeconstructCellVar, !State),
        list.foldl(cls_require_var_in_reg_with_cost(FvLoadCost),
            DeconstructFieldVars, !State)
    ;
        TuplingProposal = tupling(_, TupleFieldVars, _),
        VarsToLoad = set.difference(
            set.from_list(DeconstructFieldVars),
            set.from_list(TupleFieldVars)),
        ( set.non_empty(VarsToLoad) ->
            cls_require_var_in_reg_with_cost(CvLoadCost, DeconstructCellVar,
                !State),
            set.fold(cls_require_var_in_reg_with_cost(FvLoadCost), VarsToLoad,
                !State)
        ;
            % All the variables generated by this deconstruction can be
            % obtained from the proposed tupling, so the deconstruction
            % can be ignored. The costs of loading those variables from
            % the tuple will be counted as they come.
            true
        )
    ).

%-----------------------------------------------------------------------------%

    % Copy the given variables to the stack, if they have not been copied
    % previously.
    %
:- pred cls_require_flushed(count_info::in, set_of_progvar::in,
    count_state::in, count_state::out) is det.

cls_require_flushed(CountInfo, Vars, !CountState) :-
    TuplingProposal = get_own_tupling_proposal(CountInfo),
    TuningParams = CountInfo ^ ci_params,
    set_of_var.fold(cls_require_flushed_2(TuplingProposal, TuningParams),
        Vars, !CountState).

:- pred cls_require_flushed_2(tupling_proposal::in, tuning_params::in,
    prog_var::in, count_state::in, count_state::out) is det.

cls_require_flushed_2(no_tupling, TuningParams, Var, !CountState) :-
    StoreCost = TuningParams ^ tp_normal_var_store_cost,
    cls_require_flushed_with_cost(StoreCost, Var, !CountState).

cls_require_flushed_2(tupling(CellVar, FieldVars, _), TuningParams, Var,
        !CountState) :-
    ( list.member(Var, FieldVars) ->
        FvStoreCost = TuningParams ^ tp_field_var_store_cost,
        cls_require_flushed_with_cost(FvStoreCost, CellVar, !CountState)
    ;
        StoreCost = TuningParams ^ tp_normal_var_store_cost,
        cls_require_flushed_with_cost(StoreCost, Var, !CountState)
    ).

:- pred cls_require_flushed_with_cost(int::in, prog_var::in, count_state::in,
    count_state::out) is det.

cls_require_flushed_with_cost(StoreCost, Var,
        count_state(RegVars, StackVars0, Loads, Stores0),
        count_state(RegVars, StackVars, Loads, Stores)) :-
    ( set_of_var.member(StackVars0, Var) ->
        StackVars = StackVars0,
        Stores = Stores0
    ;
        set_of_var.insert(Var, StackVars0, StackVars),
        Stores = Stores0 + float(StoreCost)
    ).

%-----------------------------------------------------------------------------%

    % Clear out the contents of the registers and replace them with the
    % values of the given variables.
    %
:- pred cls_clobber_regs(set(prog_var)::in, count_state::in, count_state::out)
    is det.

cls_clobber_regs(NewVars, !CountState) :-
    !CountState ^ cs_reg_vars := set_to_bitset(NewVars).

%-----------------------------------------------------------------------------%

:- pred reset_count_state_counts(count_state::in, count_state::out) is det.

reset_count_state_counts(!CountState) :-
    !CountState ^ cs_load_costs := 0.0,
    !CountState ^ cs_store_costs := 0.0.

:- pred add_branch_costs(count_state::in, float::in,
    count_state::in, count_state::out) is det.

add_branch_costs(BranchState, Weight, !CountState) :-
    BranchState = count_state(_, _, BranchLoads, BranchStores),
    !.CountState = count_state(_, _, Loads0, Stores0),
    !CountState ^ cs_load_costs := Loads0 + Weight * BranchLoads,
    !CountState ^ cs_store_costs := Stores0 + Weight * BranchStores.

%-----------------------------------------------------------------------------%
%
% Building information about intervals and insert maps.
%

:- pred build_interval_info(module_info::in, proc_info::in, interval_info::out)
    is det.

build_interval_info(ModuleInfo, ProcInfo, IntervalInfo) :-
    proc_info_get_goal(ProcInfo, Goal),
    proc_info_get_vartypes(ProcInfo, VarTypes),
    arg_info.partition_proc_args(ProcInfo, ModuleInfo,
        _InputArgs, OutputArgs, _UnusedArgs),
    Counter0 = counter.init(1),
    counter.allocate(CurInterval, Counter0, Counter),
    CurIntervalId = interval_id(CurInterval),
    EndMap = map.singleton(CurIntervalId, anchor_proc_end),
    StartMap = map.init,
    SuccMap = map.singleton(CurIntervalId, []),
    VarsMap = map.singleton(CurIntervalId, set_to_bitset(OutputArgs)),
    IntParams = interval_params(ModuleInfo, VarTypes, no),
    IntervalInfo0 = interval_info(IntParams, set_of_var.init,
        set_to_bitset(OutputArgs), map.init, map.init, map.init,
        CurIntervalId, Counter,
        set.make_singleton_set(CurIntervalId),
        map.init, set.init, StartMap, EndMap,
        SuccMap, VarsMap, map.init),
    build_interval_info_in_goal(Goal, IntervalInfo0, IntervalInfo, unit, _).

    % This is needed only to satisfy the interface of interval.m
    %
:- instance build_interval_info_acc(unit) where [
    pred(use_cell/8) is tupling.use_cell
].

:- pred use_cell(prog_var::in, list(prog_var)::in, cons_id::in, hlds_goal::in,
    interval_info::in, interval_info::out, unit::in, unit::out) is det.

use_cell(_CellVar, _FieldVarList, _ConsId, _Goal, !IntervalInfo, !Unit).

%-----------------------------------------------------------------------------%

    % This predicate uses the interval information built previously to
    % build an insertion map, i.e. a mapping from a left anchor to a
    % deconstruction unification that is to be inserted _after_ the
    % interval beginning with that left anchor.
    %
:- pred build_insert_map(prog_var::in, list(prog_var)::in, interval_info::in,
    insert_map::out) is det.

build_insert_map(CellVar, FieldVars, IntervalInfo, InsertMap) :-
    FieldVarsSet = set_of_var.list_to_set(FieldVars),
    map.foldl(build_insert_map_2(CellVar, FieldVars, FieldVarsSet),
        IntervalInfo ^ ii_anchor_follow_map, map.init, InsertMap).

:- pred build_insert_map_2(prog_var::in, list(prog_var)::in,
    set_of_progvar::in, anchor::in, anchor_follow_info::in,
    insert_map::in, insert_map::out) is det.

build_insert_map_2(CellVar, FieldVars, FieldVarsSet, Anchor,
        anchor_follow_info(FollowVars, _), !InsertMap) :-
    NeededFieldVars = FieldVarsSet `set_of_var.intersect` FollowVars,
    ( set_of_var.is_empty(NeededFieldVars) ->
        true
    ;
        deconstruct_tuple(CellVar, FieldVars, Goal),
        InsertSpec = insert_spec(Goal, NeededFieldVars),
        add_insert_spec(Anchor, InsertSpec, !InsertMap)
    ).

:- pred add_insert_spec(anchor::in, insert_spec::in, insert_map::in,
    insert_map::out) is det.

add_insert_spec(Anchor, InsertSpec, !InsertMap) :-
    ( map.search(!.InsertMap, Anchor, InsertSpecs0) ->
        combine_inserts(InsertSpec, InsertSpecs0, InsertSpecs),
        map.det_update(Anchor, InsertSpecs, !InsertMap)
    ;
        map.det_insert(Anchor, [InsertSpec], !InsertMap)
    ).

:- pred combine_inserts(insert_spec::in, list(insert_spec)::in,
    list(insert_spec)::out) is det.

combine_inserts(A, [], [A]).
combine_inserts(A, [B | Bs], [C | Cs]) :-
    (
        A = insert_spec(Goal, ASet),
        B = insert_spec(Goal, BSet)
    ->
        C = insert_spec(Goal, ASet `set_of_var.union` BSet),
        Cs = Bs
    ;
        C = B,
        combine_inserts(A, Bs, Cs)
    ).

%-----------------------------------------------------------------------------%
%
% Fixing calls to transformed procedures.
%

    % The transform_map structure records which procedures were
    % transformed into what procedures.
    %
:- type transform_map == map(pred_proc_id, transformed_proc).

:- type transformed_proc
    --->    transformed_proc(
                % The pred_proc_id of the transformed version of the procedure.
                transformed_pred_proc_id    :: pred_proc_id,

                % The type of the cell variable created by the transformation.
                % This will be a tuple type.
                tuple_cons_type         :: mer_type,

                % The argument positions of the original procedure
                % which were tupled.
                args_to_tuple           :: list(int),

                % A template for a call goal that is used to update calls
                % of the original procedure to the transformed procedure
                % instead. The arguments of the template need to be replaced
                % by the actual arguments.
                call_template           :: hlds_goal
            ).

:- pred fix_calls_in_procs(transform_map::in, list(pred_proc_id)::in,
    module_info::in, module_info::out) is det.

fix_calls_in_procs(TransformMap, PredProcIds, !ModuleInfo) :-
    list.foldl(fix_calls_in_proc(TransformMap), PredProcIds, !ModuleInfo).

:- pred fix_calls_in_transformed_procs(transform_map::in,
    module_info::in, module_info::out) is det.

fix_calls_in_transformed_procs(TransformMap, !ModuleInfo) :-
    map.foldl(fix_calls_in_transformed_procs_2(TransformMap), TransformMap,
        !ModuleInfo).

:- pred fix_calls_in_transformed_procs_2(transform_map::in, pred_proc_id::in,
    transformed_proc::in, module_info::in, module_info::out) is det.

fix_calls_in_transformed_procs_2(TransformMap,
        _, transformed_proc(PredProcId, _, _, _), !ModuleInfo) :-
    fix_calls_in_proc(TransformMap, PredProcId, !ModuleInfo).

:- pred fix_calls_in_proc(transform_map::in, pred_proc_id::in,
    module_info::in, module_info::out) is det.

fix_calls_in_proc(TransformMap, proc(PredId, ProcId), !ModuleInfo) :-
    some [!ProcInfo] (
        module_info_pred_proc_info(!.ModuleInfo, PredId, ProcId,
            PredInfo, !:ProcInfo),
        % XXX: Don't modify predicates that were created by type
        % specialisation. This is a last-minute workaround for some
        % linking problems that occurred when such predicates in the
        % library were made to call tupled procedures.
        pred_info_get_origin(PredInfo, Origin),
        (
            Origin = origin_transformed(transform_type_specialization(_), _, _)
        ->
            true
        ;
            proc_info_get_goal(!.ProcInfo, Goal0),
            proc_info_get_vartypes(!.ProcInfo, VarTypes0),
            proc_info_get_varset(!.ProcInfo, VarSet0),
            proc_info_get_rtti_varmaps(!.ProcInfo, RttiVarMaps0),
            fix_calls_in_goal(Goal0, Goal, VarSet0, VarSet,
                VarTypes0, VarTypes, RttiVarMaps0, RttiVarMaps,
                TransformMap),
            proc_info_set_goal(Goal, !ProcInfo),
            proc_info_set_varset(VarSet, !ProcInfo),
            proc_info_set_vartypes(VarTypes, !ProcInfo),
            proc_info_set_rtti_varmaps(RttiVarMaps, !ProcInfo),
            requantify_proc_general(ordinary_nonlocals_no_lambda, !ProcInfo),
            recompute_instmap_delta_proc(recompute_atomic_instmap_deltas,
                !ProcInfo, !ModuleInfo),
            module_info_set_pred_proc_info(PredId, ProcId,
                PredInfo, !.ProcInfo, !ModuleInfo)
        )
    ).

%-----------------------------------------------------------------------------%

:- pred fix_calls_in_goal(hlds_goal::in, hlds_goal::out,
    prog_varset::in, prog_varset::out, vartypes::in, vartypes::out,
    rtti_varmaps::in, rtti_varmaps::out, transform_map::in) is det.

fix_calls_in_goal(Goal0, Goal, !VarSet, !VarTypes, !RttiVarMaps,
        TransformMap) :-
    Goal0 = hlds_goal(GoalExpr0, GoalInfo0),
    (
        ( GoalExpr0 = call_foreign_proc(_, _, _, _, _, _, _)
        ; GoalExpr0 = generic_call(_, _, _, _, _)
        ; GoalExpr0 = unify(_, _, _, _, _)
        ),
        Goal = hlds_goal(GoalExpr0, GoalInfo0)
    ;
        GoalExpr0 = plain_call(CalledPredId0, CalledProcId0, Args0, Builtin,
            _Context, _SymName),
        (
            Builtin = not_builtin,
            map.search(TransformMap, proc(CalledPredId0, CalledProcId0),
                TransformedProc),
            TransformedProc = transformed_proc(_, TupleConsType, ArgsToTuple,
                hlds_goal(CallAux0, CallAuxInfo))
        ->
            varset.new_named_var("TuplingCellVarForCall", CellVar, !VarSet),
            add_var_type(CellVar, TupleConsType, !VarTypes),
            extract_tupled_args_from_list(Args0, ArgsToTuple,
                TupledArgs, UntupledArgs),
            construct_tuple(CellVar, TupledArgs, ConstructGoal),
            (
                NewArgs = UntupledArgs ++ [CellVar],
                CallAux = CallAux0 ^ call_args := NewArgs
            ->
                CallGoal = hlds_goal(CallAux, CallAuxInfo)
            ;
                unexpected($module, $pred, "not a call template")
            ),
            conj_list_to_goal([ConstructGoal, CallGoal], GoalInfo0, Goal1),
            RequantifyVars = set_of_var.list_to_set([CellVar | Args0]),
            implicitly_quantify_goal_general(ordinary_nonlocals_no_lambda,
                RequantifyVars, _, Goal1, Goal,
                !VarSet, !VarTypes, !RttiVarMaps)
        ;
            Goal = hlds_goal(GoalExpr0, GoalInfo0)
        )
    ;
        GoalExpr0 = negation(SubGoal0),
        fix_calls_in_goal(SubGoal0, SubGoal, !VarSet, !VarTypes, !RttiVarMaps,
            TransformMap),
        GoalExpr = negation(SubGoal),
        Goal = hlds_goal(GoalExpr, GoalInfo0)
    ;
        GoalExpr0 = scope(Reason, SubGoal0),
        (
            Reason = from_ground_term(_, FGT),
            ( FGT = from_ground_term_construct
            ; FGT = from_ground_term_deconstruct
            )
        ->
            Goal = Goal0
        ;
            fix_calls_in_goal(SubGoal0, SubGoal, !VarSet, !VarTypes,
                !RttiVarMaps, TransformMap),
            GoalExpr = scope(Reason, SubGoal),
            Goal = hlds_goal(GoalExpr, GoalInfo0)
        )
    ;
        GoalExpr0 = conj(ConjType, Goals0),
        (
            ConjType = plain_conj,
            fix_calls_in_conj(Goals0, Goals, !VarSet, !VarTypes, !RttiVarMaps,
                TransformMap)
        ;
            ConjType = parallel_conj,
            % XXX: I am not sure whether parallel conjunctions should be
            % treated with fix_calls_in_goal or fix_calls_in_goal_list.
            % At any rate, this is untested.
            fix_calls_in_goal_list(Goals0, Goals, !VarSet, !VarTypes,
                !RttiVarMaps, TransformMap)
        ),
        GoalExpr = conj(ConjType, Goals),
        Goal = hlds_goal(GoalExpr, GoalInfo0)
    ;
        GoalExpr0 = disj(Goals0),
        fix_calls_in_goal_list(Goals0, Goals, !VarSet, !VarTypes,
            !RttiVarMaps, TransformMap),
        GoalExpr = disj(Goals),
        Goal = hlds_goal(GoalExpr, GoalInfo0)
    ;
        GoalExpr0 = switch(Var, CanFail, Cases0),
        fix_calls_in_cases(Cases0, Cases, !VarSet, !VarTypes, !RttiVarMaps,
            TransformMap),
        GoalExpr = switch(Var, CanFail, Cases),
        Goal = hlds_goal(GoalExpr, GoalInfo0)
    ;
        GoalExpr0 = if_then_else(Vars, Cond0, Then0, Else0),
        fix_calls_in_goal(Cond0, Cond, !VarSet, !VarTypes, !RttiVarMaps,
            TransformMap),
        fix_calls_in_goal(Then0, Then, !VarSet, !VarTypes, !RttiVarMaps,
            TransformMap),
        fix_calls_in_goal(Else0, Else, !VarSet, !VarTypes, !RttiVarMaps,
            TransformMap),
        GoalExpr = if_then_else(Vars, Cond, Then, Else),
        Goal = hlds_goal(GoalExpr, GoalInfo0)
    ;
        GoalExpr0 = shorthand(_),
        % These should have been expanded out by now.
        unexpected($module, $pred, "shorthand")
    ).

%-----------------------------------------------------------------------------%

:- pred fix_calls_in_conj(hlds_goals::in, hlds_goals::out,
    prog_varset::in, prog_varset::out, vartypes::in, vartypes::out,
    rtti_varmaps::in, rtti_varmaps::out, transform_map::in) is det.

fix_calls_in_conj([], [], !VarSet, !VarTypes, !RttiVarMaps, _).
fix_calls_in_conj([Goal0 | Goals0], Goals, !VarSet, !VarTypes,
        !RttiVarMaps, TransformMap) :-
    fix_calls_in_goal(Goal0, Goal1, !VarSet, !VarTypes, !RttiVarMaps,
        TransformMap),
    fix_calls_in_conj(Goals0, Goals1, !VarSet, !VarTypes, !RttiVarMaps,
        TransformMap),
    ( Goal1 = hlds_goal(conj(plain_conj, ConjGoals), _) ->
        Goals = ConjGoals ++ Goals1
    ;
        Goals = [Goal1 | Goals1]
    ).

:- pred fix_calls_in_goal_list(hlds_goals::in, hlds_goals::out,
    prog_varset::in, prog_varset::out, vartypes::in, vartypes::out,
    rtti_varmaps::in, rtti_varmaps::out, transform_map::in) is det.

fix_calls_in_goal_list([], [], !VarSet, !VarTypes, !RttiVarMaps, _).
fix_calls_in_goal_list([Goal0 | Goals0], [Goal | Goals], !VarSet, !VarTypes,
        !RttiVarMaps, TransformMap) :-
    fix_calls_in_goal(Goal0, Goal, !VarSet, !VarTypes, !RttiVarMaps,
        TransformMap),
    fix_calls_in_goal_list(Goals0, Goals, !VarSet, !VarTypes,
        !RttiVarMaps, TransformMap).

:- pred fix_calls_in_cases(list(case)::in, list(case)::out,
    prog_varset::in, prog_varset::out, vartypes::in, vartypes::out,
    rtti_varmaps::in, rtti_varmaps::out, transform_map::in) is det.

fix_calls_in_cases([], [], !VarSet, !VarTypes, !RttiVarMaps, _).
fix_calls_in_cases([Case0 | Cases0], [Case | Cases], !VarSet, !VarTypes,
        !RttiVarMaps, TransformMap) :-
    Case0 = case(MainConsId, OtherConsIds, Goal0),
    fix_calls_in_goal(Goal0, Goal, !VarSet, !VarTypes, !RttiVarMaps,
        TransformMap),
    Case = case(MainConsId, OtherConsIds, Goal),
    fix_calls_in_cases(Cases0, Cases, !VarSet, !VarTypes,
        !RttiVarMaps, TransformMap).

%-----------------------------------------------------------------------------%

    % extract_tupled_args_from_list(ArgList, Indices,
    %   Selected, NotSelected)
    %
    % Pick out the elements of ArgList by the indices given and put them
    % in the list Selected, in exactly the order that they are referenced
    % in Indices.  The list NotSelected is to contain all the elements
    % of ArgList which did not end up in Selected, in the order that they
    % appeared in ArgList.
    %
    % Note again that the ordering of Selected and NotSelected are
    % determined by different lists!
    %
:- pred extract_tupled_args_from_list(list(prog_var)::in, list(int)::in,
    list(prog_var)::out, list(prog_var)::out) is det.

extract_tupled_args_from_list(ArgList, Indices, Selected, NotSelected) :-
    list.map(list.det_index1(ArgList), Indices, Selected),
    extract_tupled_args_from_list_2(ArgList, 1, Indices, NotSelected).

:- pred extract_tupled_args_from_list_2(list(prog_var)::in, int::in,
    list(int)::in, list(prog_var)::out) is det.

extract_tupled_args_from_list_2([], _Num, _Indices, []).
extract_tupled_args_from_list_2([H | T], Num, Indices, NotSelected) :-
    ( list.member(Num, Indices) ->
        extract_tupled_args_from_list_2(T, Num+1, Indices, NotSelected)
    ;
        extract_tupled_args_from_list_2(T, Num+1, Indices, NotSelectedTail),
        NotSelected = [H | NotSelectedTail]
    ).

%-----------------------------------------------------------------------------%
%
% Trace count summaries.
%

:- pred get_proc_counts(trace_counts::in, proc_label_in_context::in,
    maybe(proc_trace_counts)::out) is det.

get_proc_counts(TraceCounts, ProcLabelInContext, MaybeProcCounts) :-
    ( map.search(TraceCounts, ProcLabelInContext, ProcCounts) ->
        MaybeProcCounts = yes(ProcCounts)
    ;
        MaybeProcCounts = no
    ).

:- pred get_proc_calls(proc_trace_counts::in, int::out) is det.

get_proc_calls(ProcCounts, Count) :-
    map.lookup(ProcCounts, port_only(port_call), ContextCount),
    Count = ContextCount ^ exec_count.

:- pred get_path_only_count(proc_trace_counts::in, reverse_goal_path::in,
    int::out) is det.

get_path_only_count(ProcCounts, GoalPath, Count) :-
    PathPort = path_only(GoalPath),
    ( map.search(ProcCounts, PathPort, ContextCount) ->
        Count = ContextCount ^ exec_count
    ;
        Count = 0
    ).

:- pred get_ite_relative_frequencies(proc_trace_counts::in,
    goal_reverse_path_map::in, goal_id::in, goal_id::in,
    float::out, float::out) is det.

get_ite_relative_frequencies(ProcCounts, ReverseGoalPathMap,
        ThenGoalId, ElseGoalId, ThenRelFreq, ElseRelFreq) :-
    map.lookup(ReverseGoalPathMap, ThenGoalId, ThenGoalPath),
    map.lookup(ReverseGoalPathMap, ElseGoalId, ElseGoalPath),
    get_path_only_count(ProcCounts, ThenGoalPath, ThenCounts),
    get_path_only_count(ProcCounts, ElseGoalPath, ElseCounts),
    Total = ThenCounts + ElseCounts,
    ( Total > 0 ->
        ThenRelFreq = float(ThenCounts) / float(Total),
        ElseRelFreq = float(ElseCounts) / float(Total)
    ;
        ThenRelFreq = 0.5,
        ElseRelFreq = 0.5
    ).

:- pred get_disjunct_relative_frequency(proc_trace_counts::in,
    goal_reverse_path_map::in, goal_id::in, float::out) is det.

get_disjunct_relative_frequency(ProcCounts, ReverseGoalPathMap,
        GoalId, RelFreq) :-
    map.lookup(ReverseGoalPathMap, GoalId, RevGoalPath),
    (
        RevGoalPath = rgp_cons(RevPrevGoalPath, LastStep),
        LastStep = step_disj(_)
    ->
        RevFirstDisjGoalPath = rgp_cons(RevPrevGoalPath, step_disj(1)),
        get_path_only_count(ProcCounts, RevGoalPath, DisjCount),
        get_path_only_count(ProcCounts, RevFirstDisjGoalPath, FirstDisjCount),
        ( FirstDisjCount = 0 ->
            RelFreq = 0.0
        ;
            RelFreq = float(DisjCount) / float(FirstDisjCount)
        )
    ;
        unexpected($module, $pred, "did not see disj(N) at head of goal path")
    ).

:- pred get_case_relative_frequency(proc_trace_counts::in,
    goal_reverse_path_map::in, goal_id::in, float::out) is det.

get_case_relative_frequency(ProcCounts, ReverseGoalPathMap, GoalId, RelFreq) :-
    map.lookup(ReverseGoalPathMap, GoalId, GoalPath),
    get_path_only_count(ProcCounts, GoalPath, CaseTotal),
    get_switch_total_count(ProcCounts, GoalPath, SwitchTotal),
    ( SwitchTotal = 0 ->
        RelFreq = 0.0
    ;
        RelFreq = float(CaseTotal) / float(SwitchTotal)
    ).

:- pred get_switch_total_count(proc_trace_counts::in, reverse_goal_path::in,
    int::out) is det.

get_switch_total_count(ProcCounts, GoalPath, Total) :-
    % XXX This is very inefficient.
    map.foldl(get_switch_total_count_2(GoalPath), ProcCounts, 0, Total).

:- pred get_switch_total_count_2(reverse_goal_path::in, path_port::in,
    line_no_and_count::in, int::in, int::out) is det.

get_switch_total_count_2(SwitchGoalPath, PathPort, LineNoAndCount,
        !TotalAcc) :-
    ( case_in_switch(SwitchGoalPath, PathPort) ->
        !:TotalAcc = !.TotalAcc + LineNoAndCount ^ exec_count
    ;
        true
    ).

:- pred case_in_switch(reverse_goal_path::in, path_port::in) is semidet.

case_in_switch(GoalPath, path_only(GoalPath)) :-
    GoalPath = rgp_cons(_, LastStep),
    LastStep = step_switch(_, _).

%-----------------------------------------------------------------------------%
:- end_module transform_hlds.tupling.
%-----------------------------------------------------------------------------%
