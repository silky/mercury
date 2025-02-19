%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 2002-2011 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: make.dependencies.m.
% Author: stayl.
%
% Code to find the dependencies for a particular target,
% e.g. module.c depends on module.m, import.int, etc.
%
%-----------------------------------------------------------------------------%

:- module make.dependencies.
:- interface.

:- import_module libs.file_util.
:- import_module libs.globals.
:- import_module make.util.

:- import_module bool.
:- import_module enum.
:- import_module io.
:- import_module maybe.
:- import_module set.
:- import_module sparse_bitset.

%-----------------------------------------------------------------------------%

    % Dependency computation does a lot of unions so we use a set
    % representation suited to that purpose, namely bitsets.  We can't store
    % module_names and dependency_files in those sets, so we keep a mapping
    % between module_name <-> module_index and dependency_file <->
    % dependency_file_index in the make_info structure and work with sets of
    % indices instead.
    %
    % sparse_bitset is faster than tree_bitset by my tests.
    %
:- type deps_set(T) == sparse_bitset(T).
% :- type deps_set(T) == tree_bitset(T).

:- type module_index.
:- instance enum(module_index).

:- type dependency_file_index.
:- instance enum(dependency_file_index).

    % find_module_deps(ModuleName, Succeeded, Deps, !Info, !IO).
    %
    % The reason we don't return maybe(Deps) is that with `--keep-going'
    % we want to do as much work as possible.
    %
:- type find_module_deps(T) ==
    pred(globals, module_index, bool, deps_set(T), make_info, make_info,
        io, io).
:- inst find_module_deps ==
    (pred(in, in, out, out, in, out, di, uo) is det).

:- type find_module_deps_plain_set(T) ==
    pred(globals, module_index, bool, set(T), make_info, make_info, io, io).
:- inst find_module_deps_plain_set ==
    (pred(in, in, out, out, in, out, di, uo) is det).

:- type dependency_file
    --->    dep_target(target_file)
                        % A target which could be made.
    ;       dep_file(file_name, maybe(option)).
                        % An ordinary file which `mmc --make' does not know
                        % how to rebuild. The option gives a list of
                        % directories in which to search.

    % Return a closure which will find the dependencies for
    % a target type given a module name.
    %
:- func target_dependencies(globals::in, module_target_type::in) =
    (find_module_deps(dependency_file_index)::out(find_module_deps)) is det.

    % Union the output set of dependencies for a given module
    % with the accumulated set. This is used with
    % foldl3_maybe_stop_at_error to iterate over a list of
    % module_names to find all target files for those modules.
    %
:- pred union_deps(find_module_deps(T)::in(find_module_deps), globals::in,
    module_index::in, bool::out, deps_set(T)::in, deps_set(T)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

:- pred union_deps_plain_set(
    find_module_deps_plain_set(T)::in(find_module_deps_plain_set),
    globals::in, module_index::in, bool::out, set(T)::in, set(T)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

:- pred deps_set_foldl3_maybe_stop_at_error(bool::in,
    foldl3_pred_with_status(T, Acc, Info, IO)::in(foldl3_pred_with_status),
    globals::in, deps_set(T)::in, bool::out, Acc::in, Acc::out,
    Info::in, Info::out, IO::di, IO::uo) is det <= enum(T).

    % Convert a list of module_names to a module_index set.
    %
:- pred module_names_to_index_set(list(module_name)::in,
    deps_set(module_index)::out, make_info::in, make_info::out) is det.

    % Convert a module_index set to a module_name set.
    %
:- pred module_index_set_to_plain_set(make_info::in,
    deps_set(module_index)::in, set(module_name)::out) is det.

    % Convert a dependency_file_index set to a dependency_file set.
    %
:- pred dependency_file_index_set_to_plain_set(make_info::in,
    deps_set(dependency_file_index)::in, set(dependency_file)::out) is det.

%-----------------------------------------------------------------------------%

    % Find all modules in the current directory which are reachable
    % (by import or include) from the given module.
    %
:- pred find_reachable_local_modules(globals::in, module_name::in, bool::out,
    set(module_name)::out, make_info::in, make_info::out,
    io::di, io::uo) is det.

    % Remove all nested modules from a list of modules.
    %
:- pred remove_nested_modules(globals::in, list(module_name)::in,
    list(module_name)::out, make_info::in, make_info::out, io::di, io::uo)
    is det.

%-----------------------------------------------------------------------------%

    % Find all modules in the current directory which are reachable (by import)
    % from the given module. Return a list of `--local-module-id' options
    % suitable for the command line.
    %
:- pred make_local_module_id_options(globals::in, module_name::in, bool::out,
    list(string)::out, make_info::in, make_info::out, io::di, io::uo) is det.

%-----------------------------------------------------------------------------%

:- pred dependency_status(globals::in, dependency_file::in,
    dependency_status::out, make_info::in, make_info::out, io::di, io::uo)
    is det.

%-----------------------------------------------------------------------------%

:- type dependencies_result
    --->    deps_up_to_date
    ;       deps_out_of_date
    ;       deps_error.

    % check_dependencies(Globals, TargetFileName, TargetFileTimestamp,
    %   BuildDepsSucceeded, Dependencies, Result, !IO)
    %
    % Check that all the dependency targets are up-to-date.
    %
:- pred check_dependencies(globals::in, file_name::in,
    maybe_error(timestamp)::in, bool::in, list(dependency_file)::in,
    dependencies_result::out, make_info::in, make_info::out,
    io::di, io::uo) is det.

    % check_dependencies(Globals, TargetFileName, TargetFileTimestamp,
    %   BuildDepsSucceeded, Dependencies, Result, !IO)
    %
    % Check that all the dependency files are up-to-date.
    %
:- pred check_dependency_timestamps(globals::in, file_name::in,
    maybe_error(timestamp)::in, bool::in, list(File)::in,
    pred(File, io, io)::(pred(in, di, uo) is det),
    list(maybe_error(timestamp))::in, dependencies_result::out,
    io::di, io::uo) is det.

%-----------------------------------------------------------------------------%

:- type cached_direct_imports.
:- func init_cached_direct_imports = cached_direct_imports.

:- type cached_transitive_dependencies.
:- func init_cached_transitive_dependencies = cached_transitive_dependencies.

:- type cached_foreign_imports.
:- func init_cached_foreign_imports = cached_foreign_imports.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module parse_tree.file_names.
:- import_module parse_tree.prog_data.

:- import_module assoc_list.
:- import_module dir.
:- import_module solutions.

%-----------------------------------------------------------------------------%
%
% Bitset indices
%

:- type module_index
    --->    module_index(int).

:- type dependency_file_index
    --->    dependency_file_index(int).

:- instance enum(module_index) where [
    to_int(module_index(I)) = I,
    from_int(I) = module_index(I)
].

:- instance enum(dependency_file_index) where [
    to_int(dependency_file_index(I)) = I,
    from_int(I) = dependency_file_index(I)
].

:- pred module_name_to_index(module_name::in, module_index::out,
    make_info::in, make_info::out) is det.

module_name_to_index(ModuleName, Index, !Info) :-
    Map0 = !.Info ^ module_index_map,
    ( version_hash_table.search(Map0 ^ mim_forward_map, ModuleName, Index0) ->
        Index = Index0
    ;
        Map0 = module_index_map(Forward0, Reverse0, Size0),
        Index = module_index(Size0),
        Size = Size0 + 1,
        version_hash_table.det_insert(ModuleName, Index, Forward0, Forward),
        TrueSize = version_array.size(Reverse0),
        ( Size > TrueSize ->
            NewSize = increase_array_size(TrueSize),
            version_array.resize(NewSize, ModuleName, Reverse0, Reverse)
        ;
            version_array.set(Size0, ModuleName, Reverse0, Reverse)
        ),
        Map = module_index_map(Forward, Reverse, Size),
        !Info ^ module_index_map := Map
    ).

:- func increase_array_size(int) = int.

increase_array_size(N) = (if N = 0 then 1 else N * 2).

:- pred module_index_to_name(make_info::in, module_index::in, module_name::out)
    is det.

module_index_to_name(Info, Index, ModuleName) :-
    Index = module_index(I),
    ModuleName = Info ^ module_index_map ^ mim_reverse_map ^ elem(I).

module_names_to_index_set(ModuleNames, IndexSet, !Info) :-
    module_names_to_index_set_2(ModuleNames, init, IndexSet, !Info).

:- pred module_names_to_index_set_2(list(module_name)::in,
    deps_set(module_index)::in, deps_set(module_index)::out,
    make_info::in, make_info::out) is det.

module_names_to_index_set_2([], !IndexSet, !Info).
module_names_to_index_set_2([ModuleName | ModuleNames], !Set, !Info) :-
    module_name_to_index(ModuleName, ModuleIndex, !Info),
    insert(ModuleIndex, !Set),
    module_names_to_index_set_2(ModuleNames, !Set, !Info).

module_index_set_to_plain_set(Info, ModuleIndices, Modules) :-
    foldl(module_index_set_to_plain_set_2(Info), ModuleIndices,
        set.init, Modules).

:- pred module_index_set_to_plain_set_2(make_info::in, module_index::in,
    set(module_name)::in, set(module_name)::out) is det.

module_index_set_to_plain_set_2(Info, ModuleIndex, !Set) :-
    module_index_to_name(Info, ModuleIndex, ModuleName),
    set.insert(ModuleName, !Set).

:- pred dependency_file_to_index(dependency_file::in,
    dependency_file_index::out, make_info::in, make_info::out) is det.

dependency_file_to_index(DepFile, Index, !Info) :-
    Map0 = !.Info ^ dep_file_index_map,
    ( version_hash_table.search(Map0 ^ dfim_forward_map, DepFile, Index0) ->
        Index = Index0
    ;
        Map0 = dependency_file_index_map(Forward0, Reverse0, Size0),
        Index = dependency_file_index(Size0),
        Size = Size0 + 1,
        version_hash_table.det_insert(DepFile, Index, Forward0, Forward),
        TrueSize = version_array.size(Reverse0),
        ( Size > TrueSize ->
            NewSize = increase_array_size(TrueSize),
            version_array.resize(NewSize, DepFile, Reverse0, Reverse)
        ;
            version_array.set(Size0, DepFile, Reverse0, Reverse)
        ),
        Map = dependency_file_index_map(Forward, Reverse, Size),
        !Info ^ dep_file_index_map := Map
    ).

:- pred index_to_dependency_file(make_info::in, dependency_file_index::in,
    dependency_file::out) is det.

index_to_dependency_file(Info, Index, DepFile) :-
    Index = dependency_file_index(Int),
    DepFile = Info ^ dep_file_index_map ^ dfim_reverse_map ^ elem(Int).

dependency_file_index_set_to_plain_set(Info, DepIndices, DepFiles) :-
    foldl(dependency_file_index_set_to_plain_set_2(Info), DepIndices,
        [], DepFilesList),
    DepFiles = set.from_list(DepFilesList).

:- pred dependency_file_index_set_to_plain_set_2(make_info::in,
    dependency_file_index::in,
    list(dependency_file)::in, list(dependency_file)::out) is det.

dependency_file_index_set_to_plain_set_2(Info, DepIndex, List0, List) :-
    index_to_dependency_file(Info, DepIndex, DepFile),
    List = [DepFile | List0].

:- pred dependency_files_to_index_set(list(dependency_file)::in,
    deps_set(dependency_file_index)::out, make_info::in, make_info::out)
    is det.

dependency_files_to_index_set(DepFiles, DepIndexSet, !Info) :-
    list.foldl2(dependency_files_to_index_set_2, DepFiles,
        init, DepIndexSet, !Info).

:- pred dependency_files_to_index_set_2(dependency_file::in,
    deps_set(dependency_file_index)::in, deps_set(dependency_file_index)::out,
    make_info::in, make_info::out) is det.

dependency_files_to_index_set_2(DepFiles, !Set, !Info) :-
    dependency_file_to_index(DepFiles, DepIndex, !Info),
    insert(DepIndex, !Set).

%-----------------------------------------------------------------------------%

:- type deps_result(T)
    --->    deps_result(
                dr_success  :: bool,
                dr_set      :: deps_set(T)
            ).

:- type module_deps_result == deps_result(module_index).

union_deps(FindDeps, Globals, ModuleIndex, Success, Deps0, Deps, !Info, !IO) :-
    FindDeps(Globals, ModuleIndex, Success, Deps1, !Info, !IO),
    Deps = union(Deps0, Deps1).

union_deps_plain_set(FindDeps, Globals, ModuleName, Success, Deps0, Deps,
        !Info, !IO) :-
    FindDeps(Globals, ModuleName, Success, Deps1, !Info, !IO),
    Deps = set.union(Deps0, Deps1).

    % Note that we go to some effort in this module to stop dependency
    % calculation as soon as possible if there are errors.
    % This is important because the calls to get_module_dependencies from
    % the dependency calculation predicates can result in every module in
    % the program being read.
    %
:- func combine_deps(find_module_deps(T)::in(find_module_deps),
    find_module_deps(T)::in(find_module_deps)) =
    (find_module_deps(T)::out(find_module_deps)) is det.

combine_deps(FindDeps1, FindDeps2) =
    combine_deps_2(FindDeps1, FindDeps2).

:- pred combine_deps_2(
    find_module_deps(T)::in(find_module_deps),
    find_module_deps(T)::in(find_module_deps),
    globals::in, module_index::in, bool::out, deps_set(T)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

combine_deps_2(FindDeps1, FindDeps2, Globals, ModuleIndex, Success, Deps,
        !Info, !IO) :-
    FindDeps1(Globals, ModuleIndex, Success1, Deps1, !Info, !IO),
    (
        Success1 = no,
        !.Info ^ keep_going = no
    ->
        Success = no,
        Deps = Deps1
    ;
        FindDeps2(Globals, ModuleIndex, Success2, Deps2, !Info, !IO),
        Success = Success1 `and` Success2,
        Deps = union(Deps1, Deps2)
    ).

:- func combine_deps_list(list(
    find_module_deps(T))::in(list_skel(find_module_deps))) =
    (find_module_deps(T)::out(find_module_deps)) is det.

combine_deps_list([]) = no_deps.
combine_deps_list([FindDeps]) = FindDeps.
combine_deps_list([FindDeps1, FindDeps2 | FindDepsTail]) =
    combine_deps(FindDeps1, combine_deps_list([FindDeps2 | FindDepsTail])).

deps_set_foldl3_maybe_stop_at_error(KeepGoing, P, Globals, Ts,
        Success, !Acc, !Info, !IO) :-
    foldl3_maybe_stop_at_error(KeepGoing, P, Globals, to_sorted_list(Ts),
        Success, !Acc, !Info, !IO).

%-----------------------------------------------------------------------------%

target_dependencies(_, module_target_source) = no_deps.
target_dependencies(Globals, module_target_errors) =
        compiled_code_dependencies(Globals).
target_dependencies(_, module_target_private_interface) =
        interface_file_dependencies.
target_dependencies(_, module_target_long_interface) =
        interface_file_dependencies.
target_dependencies(_, module_target_short_interface) =
        interface_file_dependencies.
target_dependencies(_, module_target_unqualified_short_interface) =
        module_target_source `of` self.
target_dependencies(_, module_target_track_flags) = no_deps.
target_dependencies(Globals, module_target_c_header(_)) =
        target_dependencies(Globals, module_target_c_code).
target_dependencies(Globals, module_target_c_code) =
        compiled_code_dependencies(Globals).
target_dependencies(Globals, module_target_il_code) =
        compiled_code_dependencies(Globals).
target_dependencies(_, module_target_il_asm) =
    combine_deps_list([
        module_target_il_code `of` self
    ]).
target_dependencies(Globals, module_target_csharp_code) =
        compiled_code_dependencies(Globals).
target_dependencies(Globals, module_target_java_code) =
        compiled_code_dependencies(Globals).
target_dependencies(_, module_target_java_class_code) =
        module_target_java_code `of` self.
target_dependencies(Globals, module_target_erlang_header) =
        target_dependencies(Globals, module_target_erlang_code).
target_dependencies(Globals, module_target_erlang_code) =
        compiled_code_dependencies(Globals).
target_dependencies(_, module_target_erlang_beam_code) =
    combine_deps_list([
        module_target_erlang_code `of` self,
        % The `.erl' file will -include the header files of imported modules.
        module_target_erlang_header `of` direct_imports,
        module_target_erlang_header `of` indirect_imports,
        module_target_erlang_header `of` intermod_imports
    ]).
target_dependencies(Globals, module_target_object_code(PIC)) = Deps :-
    globals.get_target(Globals, CompilationTarget),
    TargetCode = target_to_module_target_code(CompilationTarget, PIC),
    globals.lookup_bool_option(Globals, highlevel_code, HighLevelCode),

    % For --highlevel-code, the `.c' file will #include the header
    % file for all imported modules.
    (
        CompilationTarget = target_c,
        HighLevelCode = yes
    ->
        HeaderDeps = combine_deps_list([
            module_target_c_header(header_mih) `of` direct_imports,
            module_target_c_header(header_mih) `of` indirect_imports,
            module_target_c_header(header_mih) `of` parents,
            module_target_c_header(header_mih) `of` intermod_imports
        ])
    ;
        HeaderDeps = no_deps
    ),
    Deps = combine_deps_list([
        TargetCode `of` self,
        module_target_c_header(header_mh) `of` foreign_imports,
        HeaderDeps
    ]).
target_dependencies(_, module_target_intermodule_interface) =
    combine_deps_list([
        module_target_source `of` self,
        module_target_private_interface `of` parents,
        module_target_long_interface `of` non_intermod_direct_imports,
        module_target_short_interface `of` non_intermod_indirect_imports
    ]).
target_dependencies(_, module_target_analysis_registry) =
    combine_deps_list([
        module_target_source `of` self,
        module_target_private_interface `of` parents,
        module_target_long_interface `of` non_intermod_direct_imports,
        module_target_short_interface `of` non_intermod_indirect_imports,
        module_target_intermodule_interface `of` direct_imports,
        module_target_intermodule_interface `of` indirect_imports,
        module_target_intermodule_interface `of` intermod_imports
    ]).
target_dependencies(_, module_target_foreign_il_asm(_)) =
    combine_deps_list([
        module_target_il_asm `of` self,
        module_target_il_asm `of`
            filter_module_names(maybe_keep_std_lib_module, direct_imports),
        module_target_il_asm `of`
            filter_module_names(maybe_keep_std_lib_module,
                foreign_imports_lang(lang_il)),
        module_target_foreign_il_asm(lang_csharp) `of`
            filter_module_names(maybe_keep_std_lib_module,
                foreign_imports_lang(lang_csharp))
    ]).
target_dependencies(Globals, module_target_foreign_object(PIC, _)) =
    get_foreign_deps(Globals, PIC).
target_dependencies(Globals, module_target_fact_table_object(PIC, _)) =
    get_foreign_deps(Globals, PIC).
target_dependencies(_, module_target_xml_doc) =
    combine_deps_list([
        module_target_source `of` self,
        module_target_private_interface `of` parents,
        module_target_long_interface `of` non_intermod_direct_imports,
        module_target_short_interface `of` non_intermod_indirect_imports
    ]).

:- func get_foreign_deps(globals::in, pic::in) =
    (find_module_deps(dependency_file_index)::out(find_module_deps)) is det.

get_foreign_deps(Globals, PIC) = Deps :-
    globals.get_target(Globals, CompilationTarget),
    TargetCode = target_to_module_target_code(CompilationTarget, PIC),
    Deps = combine_deps_list([
        TargetCode `of` self
    ]).

:- func target_to_module_target_code(compilation_target, pic)
    = module_target_type.

target_to_module_target_code(_CompilationTarget, _PIC) = TargetCode :-
    % XXX it looks wrong to be returning module_target_c_code for
    % all compilation targets.
    TargetCode = module_target_c_code.

:- func interface_file_dependencies =
    (find_module_deps(dependency_file_index)::out(find_module_deps)) is det.

interface_file_dependencies =
    combine_deps_list([
        module_target_source `of` self,
        module_target_private_interface `of` parents,
        module_target_unqualified_short_interface `of` direct_imports,
        module_target_unqualified_short_interface `of` indirect_imports
    ]).

:- func compiled_code_dependencies(globals::in) =
    (find_module_deps(dependency_file_index)::out(find_module_deps)) is det.

compiled_code_dependencies(Globals) = Deps :-
    globals.lookup_bool_option(Globals, intermodule_optimization, IntermodOpt),
    globals.lookup_bool_option(Globals, intermodule_analysis,
        IntermodAnalysis),
    globals.lookup_bool_option(Globals, track_flags, TrackFlags),
    AnyIntermod = bool.or(IntermodOpt, IntermodAnalysis),
    (
        AnyIntermod = yes,
        Deps0 = combine_deps_list([
            module_target_intermodule_interface `of` self,
            module_target_intermodule_interface `of` intermod_imports,
            map_find_module_deps(imports,
                map_find_module_deps(parents, intermod_imports)),
            base_compiled_code_dependencies(TrackFlags)
        ])
    ;
        AnyIntermod = no,
        Deps0 = base_compiled_code_dependencies(TrackFlags)
    ),
    (
        IntermodAnalysis = yes,
        Deps = combine_deps_list([
            module_target_analysis_registry `of` self,
            module_target_analysis_registry `of` direct_imports,
            Deps0
        ])
    ;
        IntermodAnalysis = no,
        Deps = Deps0
    ).

:- func base_compiled_code_dependencies(bool::in) =
    (find_module_deps(dependency_file_index)::out(find_module_deps)) is det.

base_compiled_code_dependencies(TrackFlags) = Deps :-
    (
        TrackFlags = yes,
        Deps0 = module_target_track_flags `of` self
    ;
        TrackFlags = no,
        Deps0 = no_deps
    ),
    Deps = combine_deps_list([
        module_target_source `of` self,
        fact_table_files `files_of` self,
        foreign_include_files `files_of` self,
        map_find_module_deps(imports, self),
        Deps0
    ]).

:- func imports =
    (find_module_deps(dependency_file_index)::out(find_module_deps)) is det.

imports = combine_deps_list([
        module_target_private_interface `of` parents,
        module_target_long_interface `of` direct_imports,
        module_target_short_interface `of` indirect_imports
    ]).

:- func of(module_target_type, find_module_deps(module_index)) =
    find_module_deps(dependency_file_index).
:- mode of(in, in(find_module_deps)) = out(find_module_deps) is det.

of(FileType, FindDeps) =
    of_2(FileType, FindDeps).

:- pred of_2(module_target_type::in,
    find_module_deps(module_index)::in(find_module_deps),
    globals::in, module_index::in, bool::out,
    deps_set(dependency_file_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

of_2(FileType, FindDeps, Globals, ModuleIndex, Success, TargetFiles,
        !Info, !IO) :-
    FindDeps(Globals, ModuleIndex, Success, ModuleIndexs, !Info, !IO),
    foldl2(of_3(FileType), ModuleIndexs, init, TargetFiles, !Info).

:- pred of_3(module_target_type::in, module_index::in,
    deps_set(dependency_file_index)::in, deps_set(dependency_file_index)::out,
    make_info::in, make_info::out) is det.

of_3(FileType, ModuleIndex, !Set, !Info) :-
    module_index_to_name(!.Info, ModuleIndex, ModuleName),
    TargetFile = dep_target(target_file(ModuleName, FileType)),
    dependency_file_to_index(TargetFile, TargetFileIndex, !Info),
    insert(TargetFileIndex, !Set).

:- func files_of(find_module_deps_plain_set(dependency_file),
    find_module_deps(module_index)) = find_module_deps(dependency_file_index).
:- mode files_of(in(find_module_deps_plain_set), in(find_module_deps))
    = out(find_module_deps) is det.

files_of(FindFiles, FindDeps) =
    files_of_2(FindFiles, FindDeps).

:- pred files_of_2(
    find_module_deps_plain_set(dependency_file)::
        in(find_module_deps_plain_set),
    find_module_deps(module_index)::in(find_module_deps),
    globals::in, module_index::in, bool::out,
    deps_set(dependency_file_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

files_of_2(FindFiles, FindDeps, Globals, ModuleIndex, Success, DepIndices,
        !Info, !IO) :-
    KeepGoing = !.Info ^ keep_going,
    FindDeps(Globals, ModuleIndex, Success0, ModuleIndices, !Info, !IO),
    (
        Success0 = no,
        KeepGoing = no
    ->
        Success = no,
        DepIndices = init
    ;
        deps_set_foldl3_maybe_stop_at_error(KeepGoing,
            union_deps_plain_set(FindFiles),
            Globals, ModuleIndices, Success1, init, FileNames, !Info, !IO),
        Success = Success0 `and` Success1,
        dependency_files_to_index_set(set.to_sorted_list(FileNames),
            DepIndices, !Info)
    ).

:- pred map_find_module_deps(
    find_module_deps(T)::in(find_module_deps),
    find_module_deps(module_index)::in(find_module_deps),
    globals::in, module_index::in, bool::out, deps_set(T)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

map_find_module_deps(FindDeps2, FindDeps1, Globals, ModuleIndex, Success,
        Result, !Info, !IO) :-
    KeepGoing = !.Info ^ keep_going,
    FindDeps1(Globals, ModuleIndex, Success0, Modules0, !Info, !IO),
    (
        Success0 = no,
        KeepGoing = no
    ->
        Success = no,
        Result = init
    ;
        deps_set_foldl3_maybe_stop_at_error(KeepGoing, union_deps(FindDeps2),
            Globals, Modules0, Success1, init, Result, !Info, !IO),
        Success = Success0 `and` Success1
    ).

%-----------------------------------------------------------------------------%

:- pred no_deps(globals::in, module_index::in, bool::out, deps_set(T)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

no_deps(_, _, yes, init, !Info, !IO).

:- pred self(globals::in, module_index::in, bool::out,
    deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

self(_Globals, ModuleIndex, yes, make_singleton_set(ModuleIndex), !Info, !IO).

:- pred parents(globals::in, module_index::in, bool::out,
    deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

parents(_Globals, ModuleIndex, yes, AncestorIndices, !Info, !IO) :-
    module_index_to_name(!.Info, ModuleIndex, ModuleName),
    Ancestors = get_ancestors(ModuleName),
    module_names_to_index_set(Ancestors, AncestorIndices, !Info).

%-----------------------------------------------------------------------------%

:- type cached_direct_imports == map(module_index, module_deps_result).

init_cached_direct_imports = map.init.

:- pred direct_imports(globals::in, module_index::in, bool::out,
    deps_set(module_index)::out, make_info::in, make_info::out,
    io::di, io::uo) is det.

direct_imports(Globals, ModuleIndex, Success, Modules, !Info, !IO) :-
    ( Result0 = !.Info ^ cached_direct_imports ^ elem(ModuleIndex) ->
        Result0 = deps_result(Success, Modules)
    ;
        KeepGoing = !.Info ^ keep_going,

        non_intermod_direct_imports(Globals, ModuleIndex, Success0, Modules0,
            !Info, !IO),
        (
            Success0 = no,
            KeepGoing = no
        ->
            Success = no,
            Modules = init
        ;
            % We also read `.int' files for the modules for which we read
            % `.opt' files, and for the modules imported by those modules.
            %
            intermod_imports(Globals, ModuleIndex, Success1, IntermodModules,
                !Info,
                !IO),
            (
                Success1 = no,
                KeepGoing = no
            ->
                Success = no,
                Modules = init
            ;
                deps_set_foldl3_maybe_stop_at_error(!.Info ^ keep_going,
                    union_deps(non_intermod_direct_imports), Globals,
                    IntermodModules, Success2,
                    union(Modules0, IntermodModules), Modules1,
                    !Info, !IO),
                Success = Success0 `and` Success1 `and` Success2,
                Modules = delete(Modules1, ModuleIndex)
            )
        ),
        !Info ^ cached_direct_imports ^ elem(ModuleIndex)
            := deps_result(Success, Modules)
    ).

    % Return the modules for which `.int' files are read in a compilation
    % which does not use `--intermodule-optimization'.
    %
:- pred non_intermod_direct_imports(globals::in, module_index::in, bool::out,
    deps_set(module_index)::out, make_info::in, make_info::out,
    io::di, io::uo) is det.

non_intermod_direct_imports(Globals, ModuleIndex, Success, Modules,
        !Info, !IO) :-
    (
        !.Info ^ cached_non_intermod_direct_imports ^ elem(ModuleIndex)
            = Result
    ->
        Result = deps_result(Success, Modules)
    ;
        non_intermod_direct_imports_2(Globals, ModuleIndex, Success, Modules,
            !Info, !IO),
        !Info ^ cached_non_intermod_direct_imports ^ elem(ModuleIndex)
            := deps_result(Success, Modules)
    ).

:- pred non_intermod_direct_imports_2(globals::in, module_index::in, bool::out,
    deps_set(module_index)::out, make_info::in, make_info::out,
    io::di, io::uo) is det.

non_intermod_direct_imports_2(Globals, ModuleIndex, Success, Modules,
        !Info, !IO) :-
    module_index_to_name(!.Info, ModuleIndex, ModuleName),
    get_module_dependencies(Globals, ModuleName, MaybeImports, !Info, !IO),
    (
        MaybeImports = yes(Imports),

        % Find the direct imports of this module (modules for which we will
        % read the `.int' files).
        %
        % Note that we need to do this both for the imports of
        % this module and for the imports of its ancestors.
        % This is because if this module is a submodule, then it
        % may depend on things imported only by its ancestors.
        %
        module_names_to_index_set(Imports ^ mai_impl_deps, ImplDeps, !Info),
        module_names_to_index_set(Imports ^ mai_int_deps, IntDeps, !Info),
        Modules0 = union(ImplDeps, IntDeps),
        (
            ModuleName = qualified(ParentModule, _),
            module_name_to_index(ParentModule, ParentIndex, !Info),
            non_intermod_direct_imports(Globals, ParentIndex, Success,
                ParentImports, !Info, !IO),
            Modules = union(ParentImports, Modules0)
        ;
            ModuleName = unqualified(_),
            Success = yes,
            Modules = Modules0
        )
    ;
        MaybeImports = no,
        Success = no,
        Modules = init
    ).

%-----------------------------------------------------------------------------%

    % Return the list of modules for which we should read `.int2' files.
    %
:- pred indirect_imports(globals::in, module_index::in, bool::out,
    deps_set(module_index)::out, make_info::in, make_info::out,
    io::di, io::uo) is det.

indirect_imports(Globals, ModuleIndex, Success, Modules, !Info, !IO) :-
    indirect_imports_2(Globals, direct_imports, ModuleIndex,
        Success, Modules, !Info, !IO).

    % Return the list of modules for which we should read `.int2' files,
    % ignoring those which need to be read as a result of importing modules
    % imported by a `.opt' file.
    %
:- pred non_intermod_indirect_imports(globals::in, module_index::in, bool::out,
    deps_set(module_index)::out, make_info::in, make_info::out,
    io::di, io::uo) is det.

non_intermod_indirect_imports(Globals, ModuleIndex, Success, Modules,
        !Info, !IO) :-
    indirect_imports_2(Globals, non_intermod_direct_imports, ModuleIndex,
        Success, Modules, !Info, !IO).

:- pred indirect_imports_2(globals::in,
    find_module_deps(module_index)::in(find_module_deps),
    module_index::in, bool::out, deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

indirect_imports_2(Globals, FindDirectImports, ModuleIndex, Success,
        IndirectImports, !Info, !IO) :-
    FindDirectImports(Globals, ModuleIndex, DirectSuccess, DirectImports,
        !Info, !IO),
    % XXX The original version of this code by stayl had the line assigning
    % to KeepGoing textually *before* the call to FindDirectImports, but
    % looked up the keep_going in the version of !Info *after* that call.
    KeepGoing = !.Info ^ keep_going,
    (
        DirectSuccess = no,
        KeepGoing = no
    ->
        Success = no,
        IndirectImports = init
    ;
        deps_set_foldl3_maybe_stop_at_error(!.Info ^ keep_going,
            union_deps(find_transitive_implementation_imports), Globals,
            DirectImports, IndirectSuccess,
            init, IndirectImports0, !Info, !IO),
        IndirectImports = difference(
            delete(IndirectImports0, ModuleIndex),
            DirectImports),
        Success = DirectSuccess `and` IndirectSuccess
    ).

%-----------------------------------------------------------------------------%

    % Return the list of modules for which we should read `.opt' files.
    %
:- pred intermod_imports(globals::in, module_index::in, bool::out,
    deps_set(module_index)::out, make_info::in, make_info::out, io::di, io::uo)
    is det.

intermod_imports(Globals, ModuleIndex, Success, Modules, !Info, !IO) :-
    globals.get_any_intermod(Globals, AnyIntermod),
    (
        AnyIntermod = yes,
        globals.lookup_bool_option(Globals, read_opt_files_transitively,
            Transitive),
        (
            Transitive = yes,
            find_transitive_implementation_imports(Globals, ModuleIndex,
                Success, Modules, !Info, !IO)
        ;
            Transitive = no,
            non_intermod_direct_imports(Globals, ModuleIndex, Success,
                Modules, !Info, !IO)
        )
    ;
        AnyIntermod = no,
        Success = yes,
        Modules = init
    ).

%-----------------------------------------------------------------------------%

:- type cached_foreign_imports == map(module_index, module_deps_result).

init_cached_foreign_imports = map.init.

:- pred foreign_imports(globals::in, module_index::in, bool::out,
    deps_set(module_index)::out, make_info::in, make_info::out, io::di, io::uo)
    is det.

foreign_imports(Globals, ModuleIndex, Success, Modules, !Info, !IO) :-
    % The object file depends on the header files for the modules
    % mentioned in `:- pragma foreign_import_module' declarations
    % in the current module and the `.opt' files it imports.

    globals.get_backend_foreign_languages(Globals, Languages),
    intermod_imports(Globals, ModuleIndex, IntermodSuccess, IntermodModules,
        !Info, !IO),
    deps_set_foldl3_maybe_stop_at_error(!.Info ^ keep_going,
        union_deps(find_module_foreign_imports(set.list_to_set(Languages))),
        Globals, insert(IntermodModules, ModuleIndex),
        ForeignSuccess, init, Modules, !Info, !IO),
    Success = IntermodSuccess `and` ForeignSuccess.

:- pred find_module_foreign_imports(set(foreign_language)::in,
    globals::in, module_index::in, bool::out, deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

find_module_foreign_imports(Languages, Globals, ModuleIndex, Success,
        ForeignModules, !Info, !IO) :-
    find_transitive_implementation_imports(Globals, ModuleIndex, Success0,
        ImportedModules, !Info, !IO),
    (
        Success0 = yes,
        deps_set_foldl3_maybe_stop_at_error(!.Info ^ keep_going,
            union_deps(find_module_foreign_imports_2(Languages)),
            Globals, insert(ImportedModules, ModuleIndex),
            Success, init, ForeignModules, !Info, !IO)
    ;
        Success0 = no,
        Success = no,
        ForeignModules = init
    ).

:- pred find_module_foreign_imports_2(set(foreign_language)::in,
    globals::in, module_index::in, bool::out, deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

find_module_foreign_imports_2(Languages, Globals, ModuleIndex, Success,
        ForeignModules, !Info, !IO) :-
    % Languages should be constant for the duration of the process.
    ( Result0 = !.Info ^ cached_foreign_imports ^ elem(ModuleIndex) ->
        Result0 = deps_result(Success, ForeignModules)
    ;
        find_module_foreign_imports_3(Languages, Globals, ModuleIndex,
            Success, ForeignModules, !Info, !IO),
        !Info ^ cached_foreign_imports ^ elem(ModuleIndex)
            := deps_result(Success, ForeignModules)
    ).

:- pred find_module_foreign_imports_3(set(foreign_language)::in,
    globals::in, module_index::in, bool::out, deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

find_module_foreign_imports_3(Languages, Globals, ModuleIndex,
        Success, ForeignModules, !Info, !IO) :-
    module_index_to_name(!.Info, ModuleIndex, ModuleName),
    get_module_dependencies(Globals, ModuleName, MaybeImports, !Info, !IO),
    (
        MaybeImports = yes(Imports),
        ForeignModulesList = get_foreign_imported_modules_lang(Languages,
            Imports ^ mai_foreign_import_modules),
        module_names_to_index_set(ForeignModulesList, ForeignModules, !Info),
        Success = yes
    ;
        MaybeImports = no,
        ForeignModules = init,
        Success = no
    ).

:- func get_foreign_imported_modules(foreign_import_module_info_list) =
    list(module_name).

get_foreign_imported_modules(ForeignImportModules) =
    get_foreign_imported_modules_2(no, ForeignImportModules).

:- func get_foreign_imported_modules_lang(set(foreign_language),
    foreign_import_module_info_list) = list(module_name).

get_foreign_imported_modules_lang(Languages, ForeignImportModules) =
    get_foreign_imported_modules_2(yes(Languages), ForeignImportModules).

:- func get_foreign_imported_modules_2(maybe(set(foreign_language)),
    foreign_import_module_info_list) = list(module_name).

get_foreign_imported_modules_2(MaybeLanguages, ForeignImportModules) =
    list.filter_map(get_foreign_imported_modules_3(MaybeLanguages),
        ForeignImportModules).

:- func get_foreign_imported_modules_3(maybe(set(foreign_language)),
    foreign_import_module_info) = module_name is semidet.

get_foreign_imported_modules_3(MaybeLanguages, ForeignImportModule)
        = ForeignModule :-
    ForeignImportModule = foreign_import_module_info(Language, ForeignModule,
        _),
    (
        MaybeLanguages = yes(Languages),
        set.member(Language, Languages)
    ;
        MaybeLanguages = no
    ).

%-----------------------------------------------------------------------------%

    % foreign_imports_lang(Lang, ModuleIndex, Success, Modules, !Info, !IO)
    %
    % From the module, ModuleIndex, extract the set of modules, Modules,
    % which are mentioned in foreign_import_module declarations with the
    % specified language, Lang.
    %
:- pred foreign_imports_lang(foreign_language::in,
    globals::in, module_index::in, bool::out, deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

foreign_imports_lang(Lang, Globals, ModuleIndex, Success, Modules,
        !Info, !IO) :-
    module_index_to_name(!.Info, ModuleIndex, ModuleName),
    get_module_dependencies(Globals, ModuleName, MaybeImports, !Info, !IO),
    (
        MaybeImports = yes(Imports),
        list.filter_map(
            (pred(FI::in, M::out) is semidet :-
                FI = foreign_import_module_info(Lang, M, _)
            ), Imports ^ mai_foreign_import_modules, ModulesList),
        module_names_to_index_set(ModulesList, Modules, !Info),
        Success = yes
    ;
        MaybeImports = no,
        Modules = init,
        Success = no
    ).

%-----------------------------------------------------------------------------%

    % filter(F, P, MN, S, Ms, !Info, !IO):
    %
    % Filter the set of module_names returned from P called with MN,
    % as its input arguments with F.  The first argument to F will be MN
    % and the second argument be one of the module_names returned from P.
    %
:- pred filter_module_names(
    pred(make_info, module_index, module_index)::
        in(pred(in, in, in) is semidet),
    pred(globals, module_index, bool, deps_set(module_index),
        make_info, make_info, io, io)::
        in(pred(in, in, out, out, in, out, di, uo) is det),
    globals::in, module_index::in, bool::out,
    deps_set(module_index)::out, make_info::in, make_info::out,
    io::di, io::uo) is det.

filter_module_names(Filter, F, Globals, ModuleIndex, Success, Modules,
        !Info, !IO) :-
    F(Globals, ModuleIndex, Success, Modules0, !Info, !IO),
    Modules = filter(
        (pred(M::in) is semidet :- Filter(!.Info, ModuleIndex, M)),
        Modules0).

    % If the current module we are compiling is not in the standard library
    % and the module we are importing is then remove it, otherwise keep it.
    % When compiling with `--target il', if the current module is not in the
    % standard library, we link with mercury.dll rather than the DLL file
    % for the imported module.
    %
:- pred maybe_keep_std_lib_module(make_info::in,
    module_index::in, module_index::in) is semidet.

maybe_keep_std_lib_module(Info, CurrentModuleIndex, ImportedModuleIndex) :-
    module_index_to_name(Info, CurrentModuleIndex, CurrentModule),
    module_index_to_name(Info, ImportedModuleIndex, ImportedModule),
    \+ (
        \+ mercury_std_library_module_name(CurrentModule),
        mercury_std_library_module_name(ImportedModule)
    ).

%-----------------------------------------------------------------------------%

:- pred fact_table_files(globals::in, module_index::in,
    bool::out, set(dependency_file)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

fact_table_files(Globals, ModuleIndex, Success, Files, !Info, !IO) :-
    module_index_to_name(!.Info, ModuleIndex, ModuleName),
    get_module_dependencies(Globals, ModuleName, MaybeImports, !Info, !IO),
    (
        MaybeImports = yes(Imports),
        Success = yes,
        FilesList = map((func(File) = dep_file(File, no)),
            Imports ^ mai_fact_table_deps),
        Files = set.list_to_set(FilesList)
    ;
        MaybeImports = no,
        Success = no,
        Files = init
    ).

%-----------------------------------------------------------------------------%

:- pred foreign_include_files(globals::in, module_index::in,
    bool::out, set(dependency_file)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

foreign_include_files(Globals, ModuleIndex, Success, Files, !Info, !IO) :-
    globals.get_backend_foreign_languages(Globals, Languages),
    module_index_to_name(!.Info, ModuleIndex, ModuleName),
    get_module_dependencies(Globals, ModuleName, MaybeImports, !Info, !IO),
    (
        MaybeImports = yes(Imports),
        Success = yes,
        SourceFileName = Imports ^ mai_source_file_name,
        ForeignIncludeFiles = Imports ^ mai_foreign_include_files,
        FilesList = get_foreign_include_files(set.from_list(Languages),
            SourceFileName, ForeignIncludeFiles),
        Files = set.from_list(FilesList)
    ;
        MaybeImports = no,
        Success = no,
        Files = set.init
    ).

:- func get_foreign_include_files(set(foreign_language), file_name,
    foreign_include_file_info_list) = list(dependency_file).

get_foreign_include_files(Languages, SourceFileName, ForeignIncludes)
        = Files :-
    list.filter_map(get_foreign_include_files_2(Languages, SourceFileName),
        ForeignIncludes, Files).

:- pred get_foreign_include_files_2(set(foreign_language)::in, file_name::in,
    foreign_include_file_info::in, dependency_file::out) is semidet.

get_foreign_include_files_2(Languages, SourceFileName, ForeignInclude, File) :-
    ForeignInclude = foreign_include_file_info(Language, IncludeFileName),
    set.member(Language, Languages),
    make_include_file_path(SourceFileName, IncludeFileName, IncludePath),
    File = dep_file(IncludePath, no).

%-----------------------------------------------------------------------------%

:- type transitive_dependencies_root
    --->    transitive_dependencies_root(
                module_index,
                transitive_dependencies_type,
                module_locn
            ).

:- type transitive_dependencies_type
    --->    interface_imports
    ;       all_imports            % every import_module and use_module
    ;       all_dependencies.      % all_imports plus every include_module

:- type module_locn
    --->    local_module    % The source file for the module is in
                            % the current directory.
    ;       any_module.

:- type cached_transitive_dependencies ==
    map(transitive_dependencies_root, deps_result(module_index)).

init_cached_transitive_dependencies = map.init.

find_reachable_local_modules(Globals, ModuleName, Success, Modules, !Info,
        !IO) :-
    module_name_to_index(ModuleName, ModuleIndex, !Info),
    find_transitive_module_dependencies(Globals, all_dependencies,
        local_module, ModuleIndex, Success, Modules0, !Info, !IO),
    module_index_set_to_plain_set(!.Info, Modules0, Modules).

:- pred find_transitive_implementation_imports(globals::in, module_index::in,
    bool::out, deps_set(module_index)::out, make_info::in, make_info::out,
    io::di, io::uo) is det.

find_transitive_implementation_imports(Globals, ModuleIndex, Success, Modules,
        !Info, !IO) :-
    find_transitive_module_dependencies(Globals, all_imports, any_module,
        ModuleIndex, Success, Modules0, !Info, !IO),
    Modules = insert(Modules0, ModuleIndex).

:- pred find_transitive_interface_imports(globals::in, module_index::in,
    bool::out, deps_set(module_index)::out, make_info::in, make_info::out,
    io::di, io::uo) is det.

find_transitive_interface_imports(Globals, ModuleIndex, Success, Modules,
        !Info, !IO) :-
    find_transitive_module_dependencies(Globals, interface_imports, any_module,
        ModuleIndex, Success, Modules0, !Info, !IO),
    delete(ModuleIndex, Modules0, Modules).

:- pred find_transitive_module_dependencies(globals::in,
    transitive_dependencies_type::in, module_locn::in, module_index::in,
    bool::out, deps_set(module_index)::out, make_info::in, make_info::out,
    io::di, io::uo) is det.

find_transitive_module_dependencies(Globals, DependenciesType, ModuleLocn,
        ModuleIndex, Success, Modules, !Info, !IO) :-
    DepsRoot = transitive_dependencies_root(ModuleIndex, DependenciesType,
        ModuleLocn),
    ( Result0 = !.Info ^ cached_transitive_dependencies ^ elem(DepsRoot) ->
        Result0 = deps_result(Success, Modules)
    ;
        globals.lookup_bool_option(Globals, keep_going, KeepGoing),
        find_transitive_module_dependencies_2(KeepGoing, DependenciesType,
            ModuleLocn, Globals, ModuleIndex, Success, init, Modules,
            !Info, !IO),
        !Info ^ cached_transitive_dependencies ^ elem(DepsRoot)
            := deps_result(Success, Modules)
    ).

:- pred find_transitive_module_dependencies_2(bool::in,
    transitive_dependencies_type::in, module_locn::in, globals::in,
    module_index::in, bool::out, deps_set(module_index)::in,
    deps_set(module_index)::out, make_info::in, make_info::out,
    io::di, io::uo) is det.

find_transitive_module_dependencies_2(KeepGoing, DependenciesType, ModuleLocn,
        Globals, ModuleIndex, Success, Modules0, Modules, !Info, !IO) :-
    (
        member(ModuleIndex, Modules0)
    ->
        Success = yes,
        Modules = Modules0
    ;
        DepsRoot = transitive_dependencies_root(ModuleIndex,
            DependenciesType, ModuleLocn),
        Result0 = !.Info ^ cached_transitive_dependencies ^ elem(DepsRoot)
    ->
        Result0 = deps_result(Success, Modules1),
        Modules = union(Modules0, Modules1)
    ;
        module_index_to_name(!.Info, ModuleIndex, ModuleName),
        get_module_dependencies(Globals, ModuleName, MaybeImports, !Info, !IO),
        (
            MaybeImports = yes(Imports),
            (
                (
                    ModuleLocn = any_module
                ;
                    ModuleLocn = local_module,
                    Imports ^ mai_module_dir = dir.this_directory
                )
            ->
                (
                    % Parents don't need to be considered here.
                    % Anywhere the interface of the child module is needed,
                    % the parent must also have been imported.
                    DependenciesType = interface_imports,
                    ImportsToCheck = Imports ^ mai_int_deps
                ;
                    DependenciesType = all_dependencies,
                    ImportsToCheck = list.condense([
                        Imports ^ mai_int_deps,
                        Imports ^ mai_impl_deps,
                        Imports ^ mai_parent_deps,
                        Imports ^ mai_children,
                        get_foreign_imported_modules(
                            Imports ^ mai_foreign_import_modules)
                    ])
                ;
                    DependenciesType = all_imports,
                    ImportsToCheck = list.condense([
                        Imports ^ mai_int_deps,
                        Imports ^ mai_impl_deps,
                        Imports ^ mai_parent_deps,
                        get_foreign_imported_modules(
                            Imports ^ mai_foreign_import_modules)
                    ])
                ),
                module_names_to_index_set(ImportsToCheck, ImportsToCheckSet,
                    !Info),
                ImportingModule = !.Info ^ importing_module,
                !Info ^ importing_module := yes(ModuleName),
                Modules1 = insert(Modules0, ModuleIndex),
                deps_set_foldl3_maybe_stop_at_error(KeepGoing,
                    find_transitive_module_dependencies_2(KeepGoing,
                        DependenciesType, ModuleLocn),
                    Globals, ImportsToCheckSet, Success, Modules1, Modules,
                    !Info, !IO),
                !Info ^ importing_module := ImportingModule
            ;
                Success = yes,
                Modules = Modules0
            )
        ;
            MaybeImports = no,
            Success = no,
            Modules = Modules0
        )
    ).

%-----------------------------------------------------------------------------%

remove_nested_modules(Globals, Modules0, Modules, !Info, !IO) :-
    list.foldl3(collect_nested_modules(Globals), Modules0,
        set.init, NestedModules, !Info, !IO),
    list.negated_filter(set.contains(NestedModules), Modules0, Modules).

:- pred collect_nested_modules(globals::in, module_name::in,
    set(module_name)::in, set(module_name)::out, make_info::in, make_info::out,
    io::di, io::uo) is det.

collect_nested_modules(Globals, ModuleName, !NestedModules, !Info, !IO) :-
    get_module_dependencies(Globals, ModuleName, MaybeImports, !Info, !IO),
    (
        MaybeImports = yes(Imports),
        set.insert_list(Imports ^ mai_nested_children, !NestedModules)
    ;
        MaybeImports = no
    ).

%-----------------------------------------------------------------------------%

make_local_module_id_options(Globals, ModuleName, Success, Options,
        !Info, !IO) :-
    find_reachable_local_modules(Globals, ModuleName, Success, LocalModules,
        !Info, !IO),
    set.fold(make_local_module_id_option, LocalModules, [], Options).

:- pred make_local_module_id_option(module_name::in, list(string)::in,
    list(string)::out) is det.

make_local_module_id_option(ModuleName, Opts0, Opts) :-
    ModuleNameStr = sym_name_to_string(ModuleName),
    Opts = ["--local-module-id", ModuleNameStr | Opts0].

%-----------------------------------------------------------------------------%

:- pred check_dependencies_debug_unbuilt(globals::in, file_name::in,
    assoc_list(dependency_file, dependency_status)::in,
    io::di, io::uo) is det.

check_dependencies_debug_unbuilt(Globals, TargetFileName, UnbuiltDependencies,
        !IO) :-
    io.write_string(TargetFileName, !IO),
    io.write_string(": dependencies could not be built.\n\t", !IO),
    io.write_list(UnbuiltDependencies, ",\n\t",
        (pred((DepTarget - DepStatus)::in, !.IO::di, !:IO::uo) is det :-
            make_write_dependency_file(Globals, DepTarget, !IO),
            io.write_string(" - ", !IO),
            make_write_dependency_status(DepStatus, !IO)
        ), !IO),
    io.nl(!IO).

:- pred make_write_dependency_status(dependency_status::in, io::di, io::uo)
    is det.

make_write_dependency_status(deps_status_not_considered, !IO) :-
    io.write_string("deps_status_not_considered", !IO).
make_write_dependency_status(deps_status_being_built, !IO) :-
    io.write_string("deps_status_being_built", !IO).
make_write_dependency_status(deps_status_up_to_date, !IO) :-
    io.write_string("deps_status_up_to_date", !IO).
make_write_dependency_status(deps_status_error, !IO) :-
    io.write_string("deps_status_error", !IO).

check_dependencies(Globals, TargetFileName, MaybeTimestamp, BuildDepsSucceeded,
        DepFiles, DepsResult, !Info, !IO) :-
    list.map_foldl2(dependency_status(Globals), DepFiles, DepStatusList,
        !Info, !IO),
    assoc_list.from_corresponding_lists(DepFiles, DepStatusList, DepStatusAL),
    list.filter(
        (pred((_ - DepStatus)::in) is semidet :-
            DepStatus \= deps_status_up_to_date
        ), DepStatusAL, UnbuiltDependencies),
    (
        UnbuiltDependencies = [_ | _],
        debug_msg(Globals,
            check_dependencies_debug_unbuilt(Globals, TargetFileName,
                UnbuiltDependencies),
            !IO),
        DepsResult = deps_error
    ;
        UnbuiltDependencies = [],
        debug_msg(Globals,
            io.write_string(TargetFileName ++ ": finished dependencies\n"),
            !IO),
        list.map_foldl2(get_dependency_timestamp(Globals), DepFiles,
            DepTimestamps, !Info, !IO),

        check_dependency_timestamps(Globals, TargetFileName, MaybeTimestamp,
            BuildDepsSucceeded, DepFiles, make_write_dependency_file(Globals),
            DepTimestamps, DepsResult, !IO)
    ).

:- pred check_dependencies_timestamps_write_missing_deps(file_name::in,
    bool::in, list(File)::in, pred(File, io, io)::(pred(in, di, uo) is det),
    list(maybe_error(timestamp))::in, io::di, io::uo) is det.

check_dependencies_timestamps_write_missing_deps(TargetFileName,
        BuildDepsSucceeded, DepFiles, WriteDepFile, DepTimestamps, !IO) :-
    assoc_list.from_corresponding_lists(DepFiles, DepTimestamps,
        DepTimestampAL),
    solutions(
        (pred(DepFile::out) is nondet :-
            list.member(DepFile - error(_), DepTimestampAL)
        ), ErrorDeps),
    io.write_string("** dependencies for `", !IO),
    io.write_string(TargetFileName, !IO),
    io.write_string("' do not exist: ", !IO),
    io.write_list(ErrorDeps, ", ", WriteDepFile, !IO),
    io.nl(!IO),
    (
        BuildDepsSucceeded = yes,
        io.write_string("** This indicates a bug in `mmc --make'.\n", !IO)
    ;
        BuildDepsSucceeded = no
    ).

check_dependency_timestamps(Globals, TargetFileName, MaybeTimestamp,
        BuildDepsSucceeded, DepFiles, WriteDepFile, DepTimestamps,
        DepsResult, !IO) :-
    (
        MaybeTimestamp = error(_),
        DepsResult = deps_out_of_date,
        debug_msg(Globals,
            io.write_string(TargetFileName ++ " does not exist.\n"), !IO)
    ;
        MaybeTimestamp = ok(Timestamp),
        globals.lookup_bool_option(Globals, rebuild, Rebuild),
        (
            error_in_timestamps(DepTimestamps)
        ->
            DepsResult = deps_error,
            WriteMissingDeps =
                check_dependencies_timestamps_write_missing_deps(
                    TargetFileName, BuildDepsSucceeded, DepFiles,
                    WriteDepFile, DepTimestamps),
            (
                BuildDepsSucceeded = yes,

                % Something has gone wrong -- building the target has
                % succeeded, but there are some files missing.
                % Report an error.

                WriteMissingDeps(!IO)
            ;
                BuildDepsSucceeded = no,
                debug_msg(Globals, WriteMissingDeps, !IO)
            )
        ;
            (
                Rebuild = yes,
                % With `--rebuild', a target is always considered to be
                % out-of-date, regardless of the timestamps of its
                % dependencies.
                DepsResult = deps_out_of_date
            ;
                Rebuild = no,
                ( newer_timestamp(DepTimestamps, Timestamp) ->
                    debug_newer_dependencies(Globals, TargetFileName,
                        MaybeTimestamp, DepFiles, DepTimestamps, !IO),
                    DepsResult = deps_out_of_date
                ;
                    DepsResult = deps_up_to_date
                )
            )
        )
    ).

:- pred error_in_timestamps(list(maybe_error(timestamp))::in) is semidet.

error_in_timestamps([H | T]) :-
    ( H = error(_)
    ; error_in_timestamps(T)
    ).

:- pred newer_timestamp(list(maybe_error(timestamp))::in, timestamp::in)
    is semidet.

newer_timestamp([H | T], Timestamp) :-
    (
        H = ok(DepTimestamp),
        compare((>), DepTimestamp, Timestamp)
    ;
        newer_timestamp(T, Timestamp)
    ).

:- pred debug_newer_dependencies(globals::in, string::in,
    maybe_error(timestamp)::in, list(T)::in, list(maybe_error(timestamp))::in,
    io::di, io::uo) is det.

debug_newer_dependencies(Globals, TargetFileName, MaybeTimestamp,
        DepFiles, DepTimestamps, !IO) :-
    debug_msg(Globals,
        debug_newer_dependencies_2(TargetFileName, MaybeTimestamp,
            DepFiles, DepTimestamps),
        !IO).

:- pred debug_newer_dependencies_2(string::in, maybe_error(timestamp)::in,
    list(T)::in, list(maybe_error(timestamp))::in, io::di, io::uo) is det.

debug_newer_dependencies_2(TargetFileName, MaybeTimestamp,
        DepFiles, DepTimestamps, !IO) :-
    io.write_string(TargetFileName, !IO),
    io.write_string(" [", !IO),
    io.write(MaybeTimestamp, !IO),
    io.write_string("]: newer dependencies:\n", !IO),
    assoc_list.from_corresponding_lists(DepFiles, DepTimestamps,
        DepTimestampAL),
    solutions(
        (pred({DepFile, MaybeDepTimestamp}::out) is nondet :-
            list.member(DepFile - MaybeDepTimestamp, DepTimestampAL),
            (
                MaybeDepTimestamp = error(_)
            ;
                MaybeDepTimestamp = ok(DepTimestamp),
                MaybeTimestamp = ok(Timestamp),
                compare((>), DepTimestamp, Timestamp)
            )
        ), NewerDeps),
    make_write_dependency_file_and_timestamp_list(NewerDeps, !IO).

:- pred make_write_dependency_file_and_timestamp_list(
    list({T, maybe_error(timestamp)})::in, io::di, io::uo) is det.

make_write_dependency_file_and_timestamp_list([], !IO).
make_write_dependency_file_and_timestamp_list([Head | Tail], !IO) :-
    Head = {DepFile, MaybeTimestamp},
    io.write_char('\t', !IO),
    io.write(DepFile, !IO),
    io.write_char(' ', !IO),
    io.write(MaybeTimestamp, !IO),
    io.nl(!IO),
    make_write_dependency_file_and_timestamp_list(Tail, !IO).

dependency_status(Globals, Dep, Status, !Info, !IO) :-
    (
        Dep = dep_file(_FileName, _),
        DepStatusMap = !.Info ^ dependency_status,
        ( version_hash_table.search(DepStatusMap, Dep, StatusPrime) ->
            Status = StatusPrime
        ;
            get_dependency_timestamp(Globals, Dep, MaybeTimestamp, !Info, !IO),
            (
                MaybeTimestamp = ok(_),
                Status = deps_status_up_to_date
            ;
                MaybeTimestamp = error(Error),
                Status = deps_status_error,
                io.write_string("** Error: ", !IO),
                io.write_string(Error, !IO),
                io.nl(!IO)
            ),
            !Info ^ dependency_status ^ elem(Dep) := Status
        )
    ;
        Dep = dep_target(Target),
        Target = target_file(ModuleName, FileType),
        (
            ( FileType = module_target_source
            ; FileType = module_target_track_flags
            )
        ->
            % Source files are always up-to-date.
            % .track_flags should already have been made, if required,
            % so are also up-to-date.
            ModuleTarget = module_target(module_target_source),
            maybe_warn_up_to_date_target(Globals, ModuleName - ModuleTarget,
                !Info, !IO),
            Status = deps_status_up_to_date
        ;
            DepStatusMap = !.Info ^ dependency_status,
            version_hash_table.search(DepStatusMap, Dep, StatusPrime)
        ->
            Status = StatusPrime
        ;
            get_module_dependencies(Globals, ModuleName, MaybeImports,
                !Info, !IO),
            (
                MaybeImports = no,
                Status = deps_status_error
            ;
                MaybeImports = yes(Imports),
                ( Imports ^ mai_module_dir \= dir.this_directory ->
                    % Targets from libraries are always considered to be
                    % up-to-date if they exist.

                    get_target_timestamp(Globals, do_search, Target,
                        MaybeTimestamp, !Info, !IO),
                    (
                        MaybeTimestamp = ok(_),
                        Status = deps_status_up_to_date
                    ;
                        MaybeTimestamp = error(Error),
                        Status = deps_status_error,
                        io.write_string("** Error: file `", !IO),
                        make_write_target_file(Globals, Target, !IO),
                        io.write_string("' not found: ", !IO),
                        io.write_string(Error, !IO),
                        io.nl(!IO)
                    )
                ;
                    Status = deps_status_not_considered
                )
            ),
            !Info ^ dependency_status ^ elem(Dep) := Status
        )
    ).

%-----------------------------------------------------------------------------%
:- end_module make.dependencies.
%-----------------------------------------------------------------------------%
