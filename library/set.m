%---------------------------------------------------------------------------%
% vim: ts=4 sw=4 et ft=mercury
%---------------------------------------------------------------------------%
% Copyright (C) 1994-1997, 1999-2012 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% File: set.m.
% Main authors: conway, fjh, benyi.
% Stability: high.
%
% This module provides a set ADT.
% The implementation represents sets using ordered lists.
% This file just calls the equivalent predicates in set_ordlist.
%
%--------------------------------------------------------------------------%
%--------------------------------------------------------------------------%

:- module set.
:- interface.

:- import_module bool.
:- import_module list.

%--------------------------------------------------------------------------%

:- type set(T).

    % `init(Set)' is true iff `Set' is an empty set.
    %
:- func init = set(T).
:- pred init(set(T)::uo) is det.

    % `list_to_set(List, Set)' is true iff `Set' is the set
    % containing only the members of `List'.
    %
:- pred list_to_set(list(T)::in, set(T)::out) is det.
:- func list_to_set(list(T)) = set(T).

    % Synonyms for list_to_set/1.
    %
:- func from_list(list(T)) = set(T).
:- func set(list(T)) = set(T).

    % `sorted_list_to_set(List, Set)' is true iff `Set' is the set
    % containing only the members of `List'.  `List' must be sorted
    % and must not contain any duplicates.
    %
:- pred sorted_list_to_set(list(T)::in, set(T)::out) is det.
:- func sorted_list_to_set(list(T)) = set(T).

    % A synonym for sorted_list_to_set/1.
    %
:- func from_sorted_list(list(T)) = set(T).

    % `to_sorted_list(Set, List)' is true iff `List' is the list
    % of all the members of `Set', in sorted order without any
    % duplicates.
    %
:- pred to_sorted_list(set(T)::in, list(T)::out) is det.
:- func to_sorted_list(set(T)) = list(T).

    % `singleton_set(Elem, Set)' is true iff `Set' is the set
    % containing just the single element `Elem'.
    %
:- pred singleton_set(T, set(T)).
:- mode singleton_set(in, out) is det.
:- mode singleton_set(out, in) is semidet.

:- func make_singleton_set(T) = set(T).

:- pred is_singleton(set(T)::in, T::out) is semidet.

    % `equal(SetA, SetB)' is true iff
    % `SetA' and `SetB' contain the same elements.
    %
:- pred equal(set(T)::in, set(T)::in) is semidet.

:- pred empty(set(T)::in) is semidet.

:- pred non_empty(set(T)::in) is semidet.

    % A synonym for empty/1.
    %
:- pred is_empty(set(T)::in) is semidet.

    % `subset(SetA, SetB)' is true iff `SetA' is a subset of `SetB'.
    %
:- pred subset(set(T)::in, set(T)::in) is semidet.

    % `superset(SetA, SetB)' is true iff `SetA' is a
    % superset of `SetB'.
    %
:- pred superset(set(T)::in, set(T)::in) is semidet.

    % `member(X, Set)' is true iff `X' is a member of `Set'.
    %
:- pred member(T, set(T)).
:- mode member(in, in) is semidet.
:- mode member(out, in) is nondet.

    % `set_is_member(X, Set, Result)' returns
    % `Result = yes' iff `X' is a member of `Set'.
    %
:- pred is_member(T::in, set(T)::in, bool::out) is det.

    % `contains(Set, X)' is true iff `X' is a member of `Set'.
    %
:- pred contains(set(T)::in, T::in) is semidet.

    % `insert(X, Set0, Set)' is true iff `Set' is the union of
    % `Set0' and the set containing only `X'.
    %
:- func insert(set(T), T) = set(T).
:- pred insert(T::in, set(T)::in, set(T)::out) is det.

    % `insert_new(X, Set0, Set)' is true iff `Set0' does not contain
    % `X', and `Set' is the union of `Set0' and the set containing only `X'.
    %
:- pred insert_new(T::in, set(T)::in, set(T)::out) is semidet.

    % `insert_list(Xs, Set0, Set)' is true iff `Set' is the union of
    % `Set0' and the set containing only the members of `Xs'.
    %
:- func insert_list(set(T), list(T)) = set(T).
:- pred insert_list(list(T)::in, set(T)::in, set(T)::out) is det.

    % `delete(X, Set0, Set)' is true iff `Set' is the relative
    % complement of `Set0' and the set containing only `X', i.e.
    % if `Set' is the set which contains all the elements of `Set0'
    % except `X'.
    %
:- func delete(set(T), T) = set(T).
:- pred delete(T::in, set(T)::in, set(T)::out) is det.

    % `delete_list(Set0, Xs, Set)' is true iff `Set' is the relative
    % complement of `Set0' and the set containing only the members of
    % `Xs'.
    %
:- func delete_list(set(T), list(T)) = set(T).
:- pred delete_list(list(T)::in, set(T)::in, set(T)::out) is det.

    % `remove(X, Set0, Set)' is true iff `Set0' contains `X',
    % and `Set' is the relative complement of `Set0' and the set
    % containing only `X', i.e.  if `Set' is the set which contains
    % all the elements of `Set0' except `X'.
    %
:- pred remove(T::in, set(T)::in, set(T)::out) is semidet.

    % `remove_list(Xs, Set0, Set)' is true iff `Xs' does not
    % contain any duplicates, `Set0' contains every member of `Xs',
    % and `Set' is the relative complement of `Set0' and the set
    % containing only the members of `Xs'.
    %
:- pred remove_list(list(T)::in, set(T)::in, set(T)::out) is semidet.

    % `remove_least(Elem, Set0, Set)' is true iff
    % `Set0' is not empty, `Elem' is the smallest element in `Set0'
    % (with elements ordered using the standard ordering given
    % by compare/3), and `Set' is the set containing all the
    % elements of `Set0' except `Elem'.
    %
:- pred remove_least(T::out, set(T)::in, set(T)::out) is semidet.

    % `union(SetA, SetB, Set)' is true iff `Set' is the union of
    % `SetA' and `SetB'.  If the sets are known to be of different
    % sizes, then for efficiency make `SetA' the larger of the two.
    % (The current implementation using sorted lists with duplicates
    % removed is not sensitive to the ordering of the input arguments,
    % but other set implementations may be, so observing this convention
    % will make it less likely that you will encounter problems if
    % the implementation is changed.)
    %
:- func union(set(T), set(T)) = set(T).
:- pred union(set(T)::in, set(T)::in, set(T)::out) is det.

    % `union_list(A, B)' is true iff `B' is the union of
    % all the sets in `A'.
    %
:- func union_list(list(set(T))) = set(T).

    % `power_union(A, B)' is true iff `B' is the union of
    % all the sets in `A'.
    %
:- func power_union(set(set(T))) = set(T).
:- pred power_union(set(set(T))::in, set(T)::out) is det.

    % `intersect(SetA, SetB, Set)' is true iff `Set' is the
    % intersection of `SetA' and `SetB'. If the two sets are
    % known to be unequal in size, then making SetA be the larger
    % set will usually be more efficient.
    % (The current implementation, using sorted lists with duplicates
    % removed is not sensitive to the ordering of the input arguments
    % but other set implementations may be, so observing this convention
    % will make it less likely that you will encounter problems if
    % the implementation is changed.)
    %
:- func intersect(set(T), set(T)) = set(T).
:- pred intersect(set(T)::in, set(T)::in, set(T)::out) is det.

    % `power_intersect(A, B)' is true iff `B' is the intersection of
    % all the sets in `A'.
    %
:- func power_intersect(set(set(T))) = set(T).
:- pred power_intersect(set(set(T))::in, set(T)::out) is det.

    % `intersect_list(A, B)' is true iff `B' is the intersection of
    % all the sets in `A'.
    %
:- func intersect_list(list(set(T))) = set(T).

    % `difference(SetA, SetB, Set)' is true iff `Set' is the
    % set containing all the elements of `SetA' except those that
    % occur in `SetB'.
    %
:- func difference(set(T), set(T)) = set(T).
:- pred difference(set(T)::in, set(T)::in, set(T)::out) is det.

    % `count(Set, Count)' is true iff `Set' has `Count' elements.
    % i.e. `Count' is the cardinality (size) of the 
    %
:- func count(set(T)) = int.
:- pred count(set(T)::in, int::out) is det.

    % Support for higher order set processing.

    % map(F, S) =
    %   list_to_set(list.map(F, to_sorted_list(S))).
    %
:- func map(func(T1) = T2, set(T1)) = set(T2).
:- pred map(pred(T1, T2), set(T1), set(T2)).
:- mode map(pred(in, out) is det, in, out) is det.
:- mode map(pred(in, out) is cc_multi, in, out) is cc_multi.
:- mode map(pred(in, out) is semidet, in, out) is semidet.
:- mode map(pred(in, out) is multi, in, out) is multi.
:- mode map(pred(in, out) is nondet, in, out) is nondet.

    % map_fold(P, S0, S, A0, A) :-
    %   L0 = to_sorted_list(S0),
    %   list.map_foldl(P, L0, L, A0, A),
    %   S = list_to_set(L).
    %
:- pred map_fold(pred(T1, T2, T3, T3), set(T1), set(T2), T3, T3).
:- mode map_fold(pred(in, out, in, out) is det, in, out, in, out) is det.
:- mode map_fold(pred(in, out, mdi, muo) is det, in, out, mdi, muo) is det.
:- mode map_fold(pred(in, out, di, uo) is det, in, out, di, uo) is det.
:- mode map_fold(pred(in, out, in, out) is semidet, in, out,
    in, out) is semidet.
:- mode map_fold(pred(in, out, mdi, muo) is semidet, in, out,
    mdi, muo) is semidet.
:- mode map_fold(pred(in, out, di, uo) is semidet, in, out,
    di, uo) is semidet.

    % Return the set of items for which the given predicate succeeds.
    % filter(P, S) =
    %   sorted_list_to_set(list.filter(P, to_sorted_list(S))).
    %
:- func filter(pred(T1), set(T1)) = set(T1).
:- mode filter(pred(in) is semidet, in) = out is det.
:- pred filter(pred(T1), set(T1), set(T1)).
:- mode filter(pred(in) is semidet, in, out) is det.

    % Return the set of items for which the given predicate succeeds,
    % and the set of items for which it fails.
    %
:- pred filter(pred(T1), set(T1), set(T1), set(T1)).
:- mode filter(pred(in) is semidet, in, out, out) is det.

    % filter_map(PF, S) =
    %   list_to_set(list.filter_map(PF, to_sorted_list(S))).
    %
:- pred filter_map(pred(T1, T2), set(T1), set(T2)).
:- mode filter_map(in(pred(in, out) is semidet), in, out) is det.
:- func filter_map(func(T1) = T2, set(T1)) = set(T2).
:- mode filter_map(func(in) = out is semidet, in) = out is det.

    % fold(F, S, A) =
    %   list.foldl(F, to_sorted_list(S), A).
    %
:- func fold(func(T, A) = A, set(T), A) = A.
:- func foldl(func(T, A) = A, set(T), A) = A.

:- pred fold(pred(T, A, A), set(T), A, A).
:- mode fold(pred(in, in, out) is det, in, in, out) is det.
:- mode fold(pred(in, mdi, muo) is det, in, mdi, muo) is det.
:- mode fold(pred(in, di, uo) is det, in, di, uo) is det.
:- mode fold(pred(in, in, out) is semidet, in, in, out) is semidet.
:- mode fold(pred(in, mdi, muo) is semidet, in, mdi, muo) is semidet.
:- mode fold(pred(in, di, uo) is semidet, in, di, uo) is semidet.

:- pred foldl(pred(T, A, A), set(T), A, A).
:- mode foldl(pred(in, in, out) is det, in, in, out) is det.
:- mode foldl(pred(in, mdi, muo) is det, in, mdi, muo) is det.
:- mode foldl(pred(in, di, uo) is det, in, di, uo) is det.
:- mode foldl(pred(in, in, out) is semidet, in, in, out) is semidet.
:- mode foldl(pred(in, mdi, muo) is semidet, in, mdi, muo) is semidet.
:- mode foldl(pred(in, di, uo) is semidet, in, di, uo) is semidet.

:- pred fold2(pred(T, A, A, B, B), set(T), A, A, B, B).
:- mode fold2(pred(in, in, out, in, out) is det, in,
    in, out, in, out) is det.
:- mode fold2(pred(in, in, out, mdi, muo) is det, in,
    in, out, mdi, muo) is det.
:- mode fold2(pred(in, in, out, di, uo) is det, in,
    in, out, di, uo) is det.
:- mode fold2(pred(in, in, out, in, out) is semidet,
    in, in, out, in, out) is semidet.
:- mode fold2(pred(in, in, out, mdi, muo) is semidet,
    in, in, out, mdi, muo) is semidet.
:- mode fold2(pred(in, in, out, di, uo) is semidet,
    in, in, out, di, uo) is semidet.

:- pred foldl2(pred(T, A, A, B, B), set(T), A, A, B, B).
:- mode foldl2(pred(in, in, out, in, out) is det, in,
    in, out, in, out) is det.
:- mode foldl2(pred(in, in, out, mdi, muo) is det, in,
    in, out, mdi, muo) is det.
:- mode foldl2(pred(in, in, out, di, uo) is det, in,
    in, out, di, uo) is det.
:- mode foldl2(pred(in, in, out, in, out) is semidet,
    in, in, out, in, out) is semidet.
:- mode foldl2(pred(in, in, out, mdi, muo) is semidet,
    in, in, out, mdi, muo) is semidet.
:- mode foldl2(pred(in, in, out, di, uo) is semidet,
    in, in, out, di, uo) is semidet.

:- pred fold3(pred(T, A, A, B, B, C, C), set(T), A, A, B, B, C, C).
:- mode fold3(pred(in, in, out, in, out, in, out) is det, in,
    in, out, in, out, in, out) is det.
:- mode fold3(pred(in, in, out, in, out, mdi, muo) is det, in,
    in, out, in, out, mdi, muo) is det.
:- mode fold3(pred(in, in, out, in, out, di, uo) is det, in,
    in, out, in, out, di, uo) is det.
:- mode fold3(pred(in, in, out, in, out, in, out) is semidet, in,
    in, out, in, out, in, out) is semidet.
:- mode fold3(pred(in, in, out, in, out, mdi, muo) is semidet, in,
    in, out, in, out, mdi, muo) is semidet.
:- mode fold3(pred(in, in, out, in, out, di, uo) is semidet, in,
    in, out, in, out, di, uo) is semidet.

:- pred foldl3(pred(T, A, A, B, B, C, C), set(T), A, A, B, B, C, C).
:- mode foldl3(pred(in, in, out, in, out, in, out) is det, in,
    in, out, in, out, in, out) is det.
:- mode foldl3(pred(in, in, out, in, out, mdi, muo) is det, in,
    in, out, in, out, mdi, muo) is det.
:- mode foldl3(pred(in, in, out, in, out, di, uo) is det, in,
    in, out, in, out, di, uo) is det.
:- mode foldl3(pred(in, in, out, in, out, in, out) is semidet, in,
    in, out, in, out, in, out) is semidet.
:- mode foldl3(pred(in, in, out, in, out, mdi, muo) is semidet, in,
    in, out, in, out, mdi, muo) is semidet.
:- mode foldl3(pred(in, in, out, in, out, di, uo) is semidet, in,
    in, out, in, out, di, uo) is semidet.

:- pred fold4(pred(T, A, A, B, B, C, C, D, D), set(T), A, A, B, B,
    C, C, D, D).
:- mode fold4(pred(in, in, out, in, out, in, out, in, out) is det, in,
    in, out, in, out, in, out, in, out) is det.
:- mode fold4(pred(in, in, out, in, out, in, out, mdi, muo) is det, in,
    in, out, in, out, in, out, mdi, muo) is det.
:- mode fold4(pred(in, in, out, in, out, in, out, di, uo) is det, in,
    in, out, in, out, in, out, di, uo) is det.
:- mode fold4(pred(in, in, out, in, out, in, out, in, out) is semidet, in,
    in, out, in, out, in, out, in, out) is semidet.
:- mode fold4(pred(in, in, out, in, out, in, out, mdi, muo) is semidet, in,
    in, out, in, out, in, out, mdi, muo) is semidet.
:- mode fold4(pred(in, in, out, in, out, in, out, di, uo) is semidet, in,
    in, out, in, out, in, out, di, uo) is semidet.

:- pred foldl4(pred(T, A, A, B, B, C, C, D, D), set(T), A, A, B, B,
    C, C, D, D).
:- mode foldl4(pred(in, in, out, in, out, in, out, in, out) is det, in,
    in, out, in, out, in, out, in, out) is det.
:- mode foldl4(pred(in, in, out, in, out, in, out, mdi, muo) is det, in,
    in, out, in, out, in, out, mdi, muo) is det.
:- mode foldl4(pred(in, in, out, in, out, in, out, di, uo) is det, in,
    in, out, in, out, in, out, di, uo) is det.
:- mode foldl4(pred(in, in, out, in, out, in, out, in, out) is semidet, in,
    in, out, in, out, in, out, in, out) is semidet.
:- mode foldl4(pred(in, in, out, in, out, in, out, mdi, muo) is semidet, in,
    in, out, in, out, in, out, mdi, muo) is semidet.
:- mode foldl4(pred(in, in, out, in, out, in, out, di, uo) is semidet, in,
    in, out, in, out, in, out, di, uo) is semidet.

:- pred fold5(pred(T, A, A, B, B, C, C, D, D, E, E), set(T), A, A, B, B,
    C, C, D, D, E, E).
:- mode fold5(
    pred(in, in, out, in, out, in, out, in, out, in, out) is det,
    in, in, out, in, out, in, out, in, out, in, out) is det.
:- mode fold5(
    pred(in, in, out, in, out, in, out, in, out, mdi, muo) is det,
    in, in, out, in, out, in, out, in, out, mdi, muo) is det.
:- mode fold5(
    pred(in, in, out, in, out, in, out, in, out, di, uo) is det,
    in, in, out, in, out, in, out, in, out, di, uo) is det.
:- mode fold5(
    pred(in, in, out, in, out, in, out, in, out, in, out) is semidet,
    in, in, out, in, out, in, out, in, out, in, out) is semidet.
:- mode fold5(
    pred(in, in, out, in, out, in, out, in, out, mdi, muo) is semidet,
    in, in, out, in, out, in, out, in, out, mdi, muo) is semidet.
:- mode fold5(
    pred(in, in, out, in, out, in, out, in, out, di, uo) is semidet,
    in, in, out, in, out, in, out, in, out, di, uo) is semidet.

:- pred foldl5(pred(T, A, A, B, B, C, C, D, D, E, E), set(T), A, A, B, B,
    C, C, D, D, E, E).
:- mode foldl5(
    pred(in, in, out, in, out, in, out, in, out, in, out) is det,
    in, in, out, in, out, in, out, in, out, in, out) is det.
:- mode foldl5(
    pred(in, in, out, in, out, in, out, in, out, mdi, muo) is det,
    in, in, out, in, out, in, out, in, out, mdi, muo) is det.
:- mode foldl5(
    pred(in, in, out, in, out, in, out, in, out, di, uo) is det,
    in, in, out, in, out, in, out, in, out, di, uo) is det.
:- mode foldl5(
    pred(in, in, out, in, out, in, out, in, out, in, out) is semidet,
    in, in, out, in, out, in, out, in, out, in, out) is semidet.
:- mode foldl5(
    pred(in, in, out, in, out, in, out, in, out, mdi, muo) is semidet,
    in, in, out, in, out, in, out, in, out, mdi, muo) is semidet.
:- mode foldl5(
    pred(in, in, out, in, out, in, out, in, out, di, uo) is semidet,
    in, in, out, in, out, in, out, in, out, di, uo) is semidet.

:- pred fold6(pred(T, A, A, B, B, C, C, D, D, E, E, F, F), set(T),
    A, A, B, B, C, C, D, D, E, E, F, F).
:- mode fold6(
    pred(in, in, out, in, out, in, out, in, out, in, out, in, out) is det,
    in, in, out, in, out, in, out, in, out, in, out, in, out) is det.
:- mode fold6(
    pred(in, in, out, in, out, in, out, in, out, in, out, mdi, muo) is det,
    in, in, out, in, out, in, out, in, out, in, out, mdi, muo) is det.
:- mode fold6(
    pred(in, in, out, in, out, in, out, in, out, in, out, di, uo) is det,
    in, in, out, in, out, in, out, in, out, in, out, di, uo) is det.
:- mode fold6(
    pred(in, in, out, in, out, in, out, in, out, in, out, in, out) is semidet,
    in, in, out, in, out, in, out, in, out, in, out, in, out) is semidet.
:- mode fold6(
    pred(in, in, out, in, out, in, out, in, out, in, out, mdi, muo) is semidet,
    in, in, out, in, out, in, out, in, out, in, out, mdi, muo) is semidet.
:- mode fold6(
    pred(in, in, out, in, out, in, out, in, out, in, out, di, uo) is semidet,
    in, in, out, in, out, in, out, in, out, in, out, di, uo) is semidet.

:- pred foldl6(pred(T, A, A, B, B, C, C, D, D, E, E, F, F), set(T),
    A, A, B, B, C, C, D, D, E, E, F, F).
:- mode foldl6(
    pred(in, in, out, in, out, in, out, in, out, in, out, in, out) is det,
    in, in, out, in, out, in, out, in, out, in, out, in, out) is det.
:- mode foldl6(
    pred(in, in, out, in, out, in, out, in, out, in, out, mdi, muo) is det,
    in, in, out, in, out, in, out, in, out, in, out, mdi, muo) is det.
:- mode foldl6(
    pred(in, in, out, in, out, in, out, in, out, in, out, di, uo) is det,
    in, in, out, in, out, in, out, in, out, in, out, di, uo) is det.
:- mode foldl6(
    pred(in, in, out, in, out, in, out, in, out, in, out, in, out) is semidet,
    in, in, out, in, out, in, out, in, out, in, out, in, out) is semidet.
:- mode foldl6(
    pred(in, in, out, in, out, in, out, in, out, in, out, mdi, muo) is semidet,
    in, in, out, in, out, in, out, in, out, in, out, mdi, muo) is semidet.
:- mode foldl6(
    pred(in, in, out, in, out, in, out, in, out, in, out, di, uo) is semidet,
    in, in, out, in, out, in, out, in, out, in, out, di, uo) is semidet.

    % all_true(Pred, Set) succeeds iff Pred(Element) succeeds
    % for all the elements of Set.
    %
:- pred all_true(pred(T)::in(pred(in) is semidet), set(T)::in) is semidet.

    % divide(Pred, Set, TruePart, FalsePart):
    % TruePart consists of those elements of Set for which Pred succeeds;
    % FalsePart consists of those elements of Set for which Pred fails.
    %
:- pred divide(pred(T)::in(pred(in) is semidet), set(T)::in,
    set(T)::out, set(T)::out) is det.

    % set_divide_by_set(DivideBySet, Set, InPart, OutPart):
    % InPart consists of those elements of Set which are also in DivideBySet;
    % OutPart consists of those elements of which are not in DivideBySet.
    %
:- pred divide_by_set(set(T)::in, set(T)::in, set(T)::out, set(T)::out)
    is det.

%--------------------------------------------------------------------------%
%--------------------------------------------------------------------------%

:- implementation.

% Everything below here is not intended to be part of the public interface,
% and will not be included in the Mercury library reference manual.

:- interface.

:- import_module set_ordlist.
:- import_module term.  % for var/1.

:- type set(T) == set_ordlist(T).

:- pragma type_spec(set.list_to_set/2, T = var(_)).
:- pragma type_spec(set.list_to_set/1, T = var(_)).

:- pragma type_spec(set.member(in, in), T = var(_)).

:- pragma type_spec(set.contains(in, in), T = var(_)).

:- pragma type_spec(set.insert/3, T = var(_)).
:- pragma type_spec(set.insert/2, T = var(_)).

:- pragma type_spec(set.insert_list/3, T = var(_)).
:- pragma type_spec(set.insert_list/2, T = var(_)).

:- pragma type_spec(set.union/3, T = var(_)).
:- pragma type_spec(set.union/2, T = var(_)).

:- pragma type_spec(set.intersect/3, T = var(_)).
:- pragma type_spec(set.intersect/2, T = var(_)).

:- pragma type_spec(set.difference/3, T = var(_)).
:- pragma type_spec(set.difference/2, T = var(_)).

%-----------------------------------------------------------------------------%

:- implementation.

set.init = S :-
    set.init(S).

set.init(Set) :-
    set_ordlist.init(Set).

set.make_singleton_set(T) = S :-
    set.singleton_set(T, S).

set.singleton_set(X, Set) :-
    set_ordlist.singleton_set(X, Set).

set.is_singleton(Set, X) :-
    set_ordlist.is_singleton(Set, X).

set.list_to_set(Xs) = S :-
    set.list_to_set(Xs, S).

set.sorted_list_to_set(Xs) = S :-
    set.sorted_list_to_set(Xs, S).

set.list_to_set(List, Set) :-
    set_ordlist.list_to_set(List, Set).

set.from_list(List) = set_ordlist.from_list(List).

set.set(List) = set_ordlist.from_list(List).

set.sorted_list_to_set(List, Set) :-
    set_ordlist.sorted_list_to_set(List, Set).

set.from_sorted_list(List) = set_ordlist.from_sorted_list(List).

set.to_sorted_list(S) = Xs :-
    set.to_sorted_list(S, Xs).

set.to_sorted_list(Set, List) :-
    set_ordlist.to_sorted_list(Set, List).

set.insert_list(S1, Xs) = S2 :-
    set.insert_list(Xs, S1, S2).

set.insert_list(List, !Set) :-
    set_ordlist.insert_list(List, !Set).

set.insert(S1, T) = S2 :-
    set.insert(T, S1, S2).

set.insert(X, !Set) :-
    set_ordlist.insert(X, !Set).

set.insert_new(X, !Set) :-
    set_ordlist.insert_new(X, !Set).

set.equal(SetA, SetB) :-
    set_ordlist.equal(SetA, SetB).

set.empty(Set) :-
    set_ordlist.empty(Set).

set.is_empty(Set) :-
    set_ordlist.empty(Set).

set.non_empty(Set) :-
    \+ set_ordlist.empty(Set).

set.subset(SetA, SetB) :-
    set_ordlist.subset(SetA, SetB).

set.superset(SetA, SetB) :-
    set_ordlist.superset(SetA, SetB).

:- pragma promise_equivalent_clauses(set.member/2).

set.member(X::in, Set::in) :-
    set_ordlist.is_member(X, Set, yes).
set.member(X::out, Set::in) :-
    set_ordlist.member(X, Set).

set.is_member(X, Set, Result) :-
    set_ordlist.is_member(X, Set, Result).

set.contains(Set, X) :-
    set_ordlist.contains(Set, X).

set.delete_list(S1, Xs) = S2 :-
    set.delete_list(Xs, S1, S2).

set.delete_list(List, !Set) :-
    set_ordlist.delete_list(List, !Set).

set.delete(S1, T) = S2 :-
    set.delete(T, S1, S2).

set.delete(X, !Set) :-
    set_ordlist.delete(X, !Set).

set.remove_list(List, !Set) :-
    set_ordlist.remove_list(List, !Set).

set.remove(X, !Set) :-
    set_ordlist.remove(X, !Set).

set.remove_least(X, !Set) :-
    set_ordlist.remove_least(X, !Set).

set.union(S1, S2) = S3 :-
    set.union(S1, S2, S3).

set.union(SetA, SetB, Set) :-
    set_ordlist.union(SetA, SetB, Set).

set.union_list(Sets) = set_ordlist.union_list(Sets).

set.power_union(SS) = S :-
    set.power_union(SS, S).

set.power_union(Sets, Set) :-
    set_ordlist.power_union(Sets, Set).

set.intersect(S1, S2) = S3 :-
    set.intersect(S1, S2, S3).

set.intersect(SetA, SetB, Set) :-
    set_ordlist.intersect(SetA, SetB, Set).

set.power_intersect(SS) = S :-
    set.power_intersect(SS, S).

set.difference(S1, S2) = S3 :-
    set.difference(S1, S2, S3).

set.power_intersect(Sets, Set) :-
    set_ordlist.power_intersect(Sets, Set).

set.intersect_list(Sets) = set_ordlist.intersect_list(Sets).

set.difference(SetA, SetB, Set) :-
    set_ordlist.difference(SetA, SetB, Set).

set.count(S) = N :-
    set.count(S, N).

set.count(Set, Count) :-
    set_ordlist.count(Set, Count).

set.map(P, S1, S2) :-
    set.to_sorted_list(S1, L1),
    list.map(P, L1, L2),
    set.list_to_set(L2, S2).

set.map(F, Set) = TransformedSet :-
    List = set.to_sorted_list(Set),
    TransformedList = list.map(F, List),
    TransformedSet = set.list_to_set(TransformedList).

set.map_fold(P, S0, S, A0, A) :-
    L0 = set.to_sorted_list(S0),
    list.map_foldl(P, L0, L, A0, A),
    S = set.list_to_set(L).

set.filter(P, Set) =
    set_ordlist.filter(P, Set).

set.filter(P, Set, TrueSet) :-
    set_ordlist.filter(P, Set, TrueSet).

set.filter(P, Set, TrueSet, FalseSet) :-
    set_ordlist.filter(P, Set, TrueSet, FalseSet).

set.filter_map(PF, Set) = 
    set_ordlist.filter_map(PF, Set).

set.filter_map(P, Set, TransformedTrueSet) :-
    set_ordlist.filter_map(P, Set, TransformedTrueSet).

set.fold(F, S, A) =
    set.foldl(F, S, A).

set.foldl(F, S, A) =
    set_ordlist.fold(F, S, A).

set.fold(F, S, !A) :-
    set.foldl(F, S, !A).

set.foldl(F, S, !A) :-
    set_ordlist.fold(F, S, !A).

set.fold2(F, S, !A, !B) :-
    set.foldl2(F, S, !A, !B).

set.foldl2(F, S, !A, !B) :-
    set_ordlist.fold2(F, S, !A, !B).

set.fold3(F, S, !A, !B, !C) :-
    set.foldl3(F, S, !A, !B, !C).

set.foldl3(F, S, !A, !B, !C) :-
    set_ordlist.fold3(F, S, !A, !B, !C).

set.fold4(F, S, !A, !B, !C, !D) :-
    set.foldl4(F, S, !A, !B, !C, !D).

set.foldl4(F, S, !A, !B, !C, !D) :-
    set_ordlist.fold4(F, S, !A, !B, !C, !D).

set.fold5(F, S, !A, !B, !C, !D, !E) :-
    set.foldl5(F, S, !A, !B, !C, !D, !E).

set.foldl5(F, S, !A, !B, !C, !D, !E) :-
    set_ordlist.fold5(F, S, !A, !B, !C, !D, !E).

set.fold6(F, S, !A, !B, !C, !D, !E, !F) :-
    set.foldl6(F, S, !A, !B, !C, !D, !E, !F).

set.foldl6(F, S, !A, !B, !C, !D, !E, !F) :-
    set_ordlist.fold6(F, S, !A, !B, !C, !D, !E, !F).

set.all_true(P, S) :-
    set_ordlist.all_true(P, S).

set.divide(P, Set, TruePart, FalsePart) :-
    set_ordlist.divide(P, Set, TruePart, FalsePart).

set.divide_by_set(DivideBySet, Set, TruePart, FalsePart) :-
    set_ordlist.divide_by_set(DivideBySet, Set, TruePart, FalsePart).

%--------------------------------------------------------------------------%
:- end_module set.
%--------------------------------------------------------------------------%
