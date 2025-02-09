%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%
% Copyright (C) 2003-2006, 2010-2011 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% File: type_class_info.m.
% Author: zs.
%
% This module generates the RTTI data for the global variables (or constants)
% that hold the data structures representing the type class and instance
% declarations in the current module.
%
% For now, the data structures generated by this module are used only by the
% debugger to inform the user, not by the runtime system to invoke type class
% methods.
%
%---------------------------------------------------------------------------%

:- module backend_libs.type_class_info.
:- interface.

:- import_module backend_libs.rtti.
:- import_module hlds.
:- import_module hlds.hlds_module.
:- import_module parse_tree.
:- import_module parse_tree.prog_data.

:- import_module bool.
:- import_module list.

%---------------------------------------------------------------------------%

:- pred generate_type_class_info_rtti(module_info::in, bool::in,
    list(rtti_data)::out) is det.

:- func generate_class_constraint(prog_constraint) = tc_constraint.

:- func generate_class_name(class_id) = tc_name.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module backend_libs.pseudo_type_info.
:- import_module hlds.hlds_data.
:- import_module hlds.hlds_pred.
:- import_module hlds.hlds_rtti.
:- import_module mdbcomp.
:- import_module mdbcomp.sym_name.

:- import_module map.
:- import_module maybe.
:- import_module pair.
:- import_module require.
:- import_module term.
:- import_module varset.

%---------------------------------------------------------------------------%

% We always generate descriptors for type class declarations, since these may
% be referred to from the descriptors of function symbols with existentially
% typed arguments. We generate descriptors for type class instances only if
% requested to generate all the descriptors we can.

generate_type_class_info_rtti(ModuleInfo, GenerateAll, !:RttiDatas) :-
    module_info_get_class_table(ModuleInfo, ClassTable),
    map.to_assoc_list(ClassTable, Classes),
    list.foldl(generate_class_decl(ModuleInfo), Classes, [], !:RttiDatas),
    (
        GenerateAll = yes,
        module_info_get_instance_table(ModuleInfo, InstanceTable),
        map.to_assoc_list(InstanceTable, Instances),
        list.foldl(generate_instance_decls(ModuleInfo), Instances, !RttiDatas)
    ;
        GenerateAll = no
    ).

%---------------------------------------------------------------------------%

:- pred generate_class_decl(module_info::in,
    pair(class_id, hlds_class_defn)::in,
    list(rtti_data)::in, list(rtti_data)::out) is det.

generate_class_decl(ModuleInfo, ClassId - ClassDefn, !RttiDatas) :-
    ImportStatus = ClassDefn ^ class_status,
    InThisModule = status_defined_in_this_module(ImportStatus),
    (
        InThisModule = yes,
        TCId = generate_class_id(ModuleInfo, ClassId, ClassDefn),
        Supers = ClassDefn ^ class_supers,
        TCSupers = list.map(generate_class_constraint, Supers),
        TCVersion = type_class_info_rtti_version,
        RttiData = rtti_data_type_class_decl(
            tc_decl(TCId, TCVersion, TCSupers)),
        !:RttiDatas = [RttiData | !.RttiDatas]
    ;
        InThisModule = no
    ).

:- func generate_class_id(module_info, class_id, hlds_class_defn) = tc_id.

generate_class_id(ModuleInfo, ClassId, ClassDefn) = TCId :-
    TCName = generate_class_name(ClassId),
    ClassVars = ClassDefn ^ class_vars,
    ClassVarSet = ClassDefn ^ class_tvarset,
    list.map(varset.lookup_name(ClassVarSet), ClassVars, VarNames),
    Interface = ClassDefn ^ class_hlds_interface,
    MethodIds = list.map(generate_method_id(ModuleInfo), Interface),
    TCId = tc_id(TCName, VarNames, MethodIds).

:- func generate_method_id(module_info, hlds_class_proc) = tc_method_id.

generate_method_id(ModuleInfo, ClassProc) = MethodId :-
    ClassProc = hlds_class_proc(PredId, _ProcId),
    module_info_pred_info(ModuleInfo, PredId, PredInfo),
    MethodName = pred_info_name(PredInfo),
    Arity = pred_info_orig_arity(PredInfo),
    PredOrFunc = pred_info_is_pred_or_func(PredInfo),
    MethodId = tc_method_id(MethodName, Arity, PredOrFunc).

%---------------------------------------------------------------------------%

:- pred generate_instance_decls(module_info::in,
    pair(class_id, list(hlds_instance_defn))::in,
    list(rtti_data)::in, list(rtti_data)::out) is det.

generate_instance_decls(ModuleInfo, ClassId - Instances, !RttiDatas) :-
    list.foldl(generate_maybe_instance_decl(ModuleInfo, ClassId),
        Instances, !RttiDatas).

:- pred generate_maybe_instance_decl(module_info::in,
    class_id::in, hlds_instance_defn::in,
    list(rtti_data)::in, list(rtti_data)::out) is det.

generate_maybe_instance_decl(ModuleInfo, ClassId, InstanceDefn, !RttiDatas) :-
    ImportStatus = InstanceDefn ^ instance_status,
    Body = InstanceDefn ^ instance_body,
    (
        Body = instance_body_concrete(_),
        % Only make the RTTI structure for the type class instance if the
        % instance declaration originally came from _this_ module.
        status_defined_in_this_module(ImportStatus) = yes
    ->
        RttiData = generate_instance_decl(ModuleInfo, ClassId, InstanceDefn),
        !:RttiDatas = [RttiData | !.RttiDatas]
    ;
        true
    ).

:- func generate_instance_decl(module_info, class_id, hlds_instance_defn)
    = rtti_data.

generate_instance_decl(ModuleInfo, ClassId, Instance) = RttiData :-
    TCName = generate_class_name(ClassId),
    InstanceTypes = Instance ^ instance_types,
    InstanceTCTypes = list.map(generate_tc_type, InstanceTypes),
    TVarSet = Instance ^ instance_tvarset,
    varset.vars(TVarSet, TVars),
    TVarNums = list.map(term.var_to_int, TVars),
    TVarLength = list.length(TVarNums),
    ( list.last(TVarNums, LastTVarNum) ->
        expect(unify(TVarLength, LastTVarNum), $module, $pred,
            "tvar num mismatch"),
        NumTypeVars = TVarLength
    ;
        NumTypeVars = 0
    ),
    Constraints = Instance ^ instance_constraints,
    TCConstraints = list.map(generate_class_constraint, Constraints),
    MaybeInterface = Instance ^ instance_hlds_interface,
    (
        MaybeInterface = yes(Interface),
        MethodProcLabels = list.map(generate_method_proc_label(ModuleInfo),
            Interface)
    ;
        MaybeInterface = no,
        unexpected($module, $pred, "no interface")
    ),
    TCInstance = tc_instance(TCName, InstanceTCTypes, NumTypeVars,
        TCConstraints, MethodProcLabels),
    RttiData = rtti_data_type_class_instance(TCInstance).

:- func generate_method_proc_label(module_info, hlds_class_proc) =
    rtti_proc_label.

generate_method_proc_label(ModuleInfo, hlds_class_proc(PredId, ProcId)) =
    make_rtti_proc_label(ModuleInfo, PredId, ProcId).

%---------------------------------------------------------------------------%

generate_class_name(class_id(SymName, Arity)) = TCName :-
    (
        SymName = qualified(ModuleName, ClassName)
    ;
        SymName = unqualified(_),
        unexpected($module, $pred, "unqualified sym_name")
    ),
    TCName = tc_name(ModuleName, ClassName, Arity).

generate_class_constraint(constraint(ClassName, Types)) = TCConstr :-
    Arity = list.length(Types),
    ClassId = class_id(ClassName, Arity),
    TCClassName = generate_class_name(ClassId),
    ClassTypes = list.map(generate_tc_type, Types),
    TCConstr = tc_constraint(TCClassName, ClassTypes).

:- func generate_tc_type(mer_type) = tc_type.

generate_tc_type(Type) = TCType :-
    pseudo_type_info.construct_maybe_pseudo_type_info(Type, -1, [], TCType).

%---------------------------------------------------------------------------%

    % The version number of the runtime data structures describing type class
    % information, most of which (currently, all of which) is generated in this
    % module.
    %
    % The value returned by this function should be kept in sync with
    % MR_TYPECLASS_VERSION in runtime/mercury_typeclass_info.h.
    %
:- func type_class_info_rtti_version = int.

type_class_info_rtti_version = 0.

%---------------------------------------------------------------------------%
:- end_module backend_libs.type_class_info.
%---------------------------------------------------------------------------%
