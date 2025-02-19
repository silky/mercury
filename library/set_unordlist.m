%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%
% Copyright (C) 1995-1997,1999-2002, 2004-2006, 2010-2012 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% File: set_unordlist.m.
% Main authors: conway, fjh.
% Stability: medium.
%
% This file contains a `set' ADT.
% Sets are implemented here as unsorted lists, which may contain duplicates.
%
%--------------------------------------------------------------------------%
%--------------------------------------------------------------------------%

:- module set_unordlist.
:- interface.

:- import_module bool.
:- import_module list.

%--------------------------------------------------------------------------%

:- type set_unordlist(_T).

    % `init(Set)' is true iff `Set' is an empty set.
    %
:- func init = set_unordlist(T).
:- pred init(set_unordlist(_T)::uo) is det.

    % `list_to_set(List, Set)' is true iff `Set' is the set
    % containing only the members of `List'.
    %
:- func list_to_set(list(T)) = set_unordlist(T).
:- pred list_to_set(list(T)::in, set_unordlist(T)::out) is det.

    % A synonym for list_to_set/1.
    %
:- func from_list(list(T)) = set_unordlist(T).

    % `sorted_list_to_set(List, Set)' is true iff `Set' is the set containing
    % only the members of `List'.  `List' must be sorted.
    %
:- pred sorted_list_to_set(list(T)::in, set_unordlist(T)::out) is det.
:- func sorted_list_to_set(list(T)) = set_unordlist(T).

    % A synonym for sorted_list_to_set/1.
    %
:- func from_sorted_list(list(T)) = set_unordlist(T).

    % `to_sorted_list(Set, List)' is true iff `List' is the list of all the
    % members of `Set', in sorted order.
    %
:- pred to_sorted_list(set_unordlist(T)::in, list(T)::out) is det.
:- func to_sorted_list(set_unordlist(T)) = list(T).

    % `singleton_set(Elem, Set)' is true iff `Set' is the set
    % containing just the single element `Elem'.
    %
:- pred singleton_set(T, set_unordlist(T)).
:- mode singleton_set(in, out) is det.
:- mode singleton_set(in, in) is semidet.     % Implied.
:- mode singleton_set(out, in) is semidet.

:- func make_singleton_set(T) = set_unordlist(T).

:- pred is_singleton(set_unordlist(T)::in, T::out) is semidet.

    % `equal(SetA, SetB)' is true iff `SetA' and `SetB' contain the same
    % elements.
    %
:- pred equal(set_unordlist(T)::in, set_unordlist(T)::in) is semidet.

    % `empty(Set)' is true iff `Set' is an empty set.
    %
:- pred empty(set_unordlist(_T)::in) is semidet.

:- pred non_empty(set_unordlist(_T)::in) is semidet.

:- pred is_empty(set_unordlist(_T)::in) is semidet.

    % `subset(SetA, SetB)' is true iff `SetA' is a subset of `SetB'.
    %
:- pred subset(set_unordlist(T)::in, set_unordlist(T)::in) is semidet.

    % `superset(SetA, SetB)' is true iff `SetA' is a superset of `SetB'.
    %
:- pred superset(set_unordlist(T)::in, set_unordlist(T)::in) is semidet.

    % `member(X, Set)' is true iff `X' is a member of `Set'.
    %
:- pred member(T, set_unordlist(T)).
:- mode member(in, in) is semidet.
:- mode member(out, in) is nondet.

    % `is_member(X, Set, Result)' returns `Result = yes' iff `X' is a member of
    % `Set'.
    %
:- pred is_member(T::in, set_unordlist(T)::in, bool::out) is det.

    % `contains(Set, X)' is true iff `X' is a member of `Set'.
    %
:- pred contains(set_unordlist(T)::in, T::in) is semidet.

    % `insert(X, Set0, Set)' is true iff `Set' is the union of `Set0' and the
    % set containing only `X'.
    %
:- pred insert(T, set_unordlist(T), set_unordlist(T)).
:- mode insert(di, di, uo) is det.
:- mode insert(in, in, out) is det.

:- func insert(set_unordlist(T), T) = set_unordlist(T).

    % `insert_new(X, Set0, Set)' is true iff `Set0' does not contain `X', and
    % `Set' is the union of `Set0' and the set containing only `X'.
    %
:- pred insert_new(T::in, set_unordlist(T)::in, set_unordlist(T)::out)
    is semidet.

    % `insert_list(Xs, Set0, Set)' is true iff `Set' is the
    % union of `Set0' and the set containing only the members of `Xs'.
    %
:- pred insert_list(list(T)::in,
    set_unordlist(T)::in, set_unordlist(T)::out) is det.

:- func insert_list(set_unordlist(T), list(T))
    = set_unordlist(T).

    % `delete(X, Set0, Set)' is true iff `Set' is the relative complement of
    % `Set0' and the set containing only `X', i.e.  if `Set' is the set which
    % contains all the elements of `Set0' except `X'.
    %
:- pred delete(T, set_unordlist(T), set_unordlist(T)).
:- mode delete(in, di, uo) is det.
:- mode delete(in, in, out) is det.

:- func delete(set_unordlist(T), T) = set_unordlist(T).

    % `delete_list(Xs, Set0, Set)' is true iff `Set' is the relative complement
    % of `Set0' and the set containing only the members of `Xs'.
    %
:- pred delete_list(list(T)::in, set_unordlist(T)::in, set_unordlist(T)::out)
    is det.

:- func delete_list(set_unordlist(T), list(T)) = set_unordlist(T).

    % `remove(X, Set0, Set)' is true iff `Set0' contains `X',
    % and `Set' is the relative complement of `Set0' and the set
    % containing only `X', i.e.  if `Set' is the set which contains
    % all the elements of `Set0' except `X'.
    %
:- pred remove(T::in,
    set_unordlist(T)::in, set_unordlist(T)::out) is semidet.

    % `remove_list(Xs, Set0, Set)' is true iff Xs does not contain any
    % duplicates, `Set0' contains every member of `Xs', and `Set' is the
    % relative complement of `Set0' and the set containing only the members of
    % `Xs'.
    %
:- pred remove_list(list(T)::in,
    set_unordlist(T)::in, set_unordlist(T)::out) is semidet.

    % `remove_least(X, Set0, Set)' is true iff `X' is the least element in
    % `Set0', and `Set' is the set which contains all the elements of `Set0'
    % except `X'.
    %
:- pred remove_least(T::out,
    set_unordlist(T)::in, set_unordlist(T)::out) is semidet.

    % `union(SetA, SetB, Set)' is true iff `Set' is the union of `SetA' and
    % `SetB'.  If the sets are known to be of different sizes, then for
    % efficiency make `SetA' the larger of the two.
    %
:- pred union(set_unordlist(T)::in, set_unordlist(T)::in,
    set_unordlist(T)::out) is det.

:- func union(set_unordlist(T), set_unordlist(T)) = set_unordlist(T).

    % `union_list(A) = B' is true iff `B' is the union of all the sets in `A'
    %
:- func union_list(list(set_unordlist(T))) = set_unordlist(T).

    % `power_union(A, B)' is true iff `B' is the union of all the sets in `A'
    %
:- pred power_union(set_unordlist(set_unordlist(T))::in,
    set_unordlist(T)::out) is det.

:- func power_union(set_unordlist(set_unordlist(T))) = set_unordlist(T).

    % `intersect(SetA, SetB, Set)' is true iff `Set' is the intersection of
    % `SetA' and `SetB'.
    %
:- pred intersect(set_unordlist(T)::in, set_unordlist(T)::in,
    set_unordlist(T)::out) is det.

:- func intersect(set_unordlist(T), set_unordlist(T)) = set_unordlist(T).

    % `power_intersect(A, B)' is true iff `B' is the intersection of all the
    % sets in `A'
    %
:- pred power_intersect(set_unordlist(set_unordlist(T))::in,
    set_unordlist(T)::out) is det.

:- func power_intersect(set_unordlist(set_unordlist(T))) = set_unordlist(T).

    % `intersect_list(A, B)' is true iff `B' is the intersection of all the
    % sets in `A'
    %
:- func intersect_list(list(set_unordlist(T))) = set_unordlist(T).

    % `difference(SetA, SetB, Set)' is true iff `Set' is the set containing all
    % the elements of `SetA' except those that occur in `SetB'
    %
:- pred difference(set_unordlist(T)::in, set_unordlist(T)::in,
    set_unordlist(T)::out) is det.

:- func difference(set_unordlist(T), set_unordlist(T)) = set_unordlist(T).

:- func count(set_unordlist(T)) = int.
:- pred count(set_unordlist(T)::in, int::out) is det.

:- func map(func(T1) = T2, set_unordlist(T1)) = set_unordlist(T2).

:- func filter_map(func(T1) = T2, set_unordlist(T1)) = set_unordlist(T2).
:- mode filter_map(func(in) = out is semidet, in) = out is det.

:- func fold(func(T1, T2) = T2, set_unordlist(T1), T2) = T2.
:- pred fold(pred(T1, T2, T2), set_unordlist(T1), T2, T2).
:- mode fold(pred(in, in, out) is det, in, in, out) is det.
:- mode fold(pred(in, mdi, muo) is det, in, mdi, muo) is det.
:- mode fold(pred(in, di, uo) is det, in, di, uo) is det.
:- mode fold(pred(in, in, out) is semidet, in, in, out) is semidet.
:- mode fold(pred(in, mdi, muo) is semidet, in, mdi, muo) is semidet.
:- mode fold(pred(in, di, uo) is semidet, in, di, uo) is semidet.

:- pred fold2(pred(T1, T2, T2, T3, T3), set_unordlist(T1),
    T2, T2, T3, T3).
:- mode fold2(pred(in, in, out, in, out) is det, in,
    in, out, in, out) is det.
:- mode fold2(pred(in, in, out, mdi, muo) is det, in,
    in, out, mdi, muo) is det.
:- mode fold2(pred(in, in, out, di, uo) is det, in,
    in, out, di, uo) is det.
:- mode fold2(pred(in, in, out, in, out) is semidet, in,
    in, out, in, out) is semidet.
:- mode fold2(pred(in, in, out, mdi, muo) is semidet, in,
    in, out, mdi, muo) is semidet.
:- mode fold2(pred(in, in, out, di, uo) is semidet, in,
    in, out, di, uo) is semidet.

:- pred fold3(pred(T1, T2, T2, T3, T3, T4, T4),
    set_unordlist(T1), T2, T2, T3, T3, T4, T4).
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

:- pred fold4(pred(T1, T2, T2, T3, T3, T4, T4, T5, T5),
    set_unordlist(T1), T2, T2, T3, T3, T4, T4, T5, T5).
:- mode fold4(
    pred(in, in, out, in, out, in, out, in, out) is det, in,
    in, out, in, out, in, out, in, out) is det.
:- mode fold4(
    pred(in, in, out, in, out, in, out, mdi, muo) is det, in,
    in, out, in, out, in, out, mdi, muo) is det.
:- mode fold4(
    pred(in, in, out, in, out, in, out, di, uo) is det, in,
    in, out, in, out, in, out, di, uo) is det.
:- mode fold4(
    pred(in, in, out, in, out, in, out, in, out) is semidet, in,
    in, out, in, out, in, out, in, out) is semidet.
:- mode fold4(
    pred(in, in, out, in, out, in, out, mdi, muo) is semidet, in,
    in, out, in, out, in, out, mdi, muo) is semidet.
:- mode fold4(
    pred(in, in, out, in, out, in, out, di, uo) is semidet, in,
    in, out, in, out, in, out, di, uo) is semidet.

:- pred fold5(
    pred(T1, T2, T2, T3, T3, T4, T4, T5, T5, T6, T6),
    set_unordlist(T1), T2, T2, T3, T3, T4, T4, T5, T5, T6, T6).
:- mode fold5(
    pred(in, in, out, in, out, in, out, in, out, in, out) is det, in,
    in, out, in, out, in, out, in, out, in, out) is det.
:- mode fold5(
    pred(in, in, out, in, out, in, out, in, out, mdi, muo) is det, in,
    in, out, in, out, in, out, in, out, mdi, muo) is det.
:- mode fold5(
    pred(in, in, out, in, out, in, out, in, out, di, uo) is det, in,
    in, out, in, out, in, out, in, out, di, uo) is det.
:- mode fold5(
    pred(in, in, out, in, out, in, out, in, out, in, out) is semidet, in,
    in, out, in, out, in, out, in, out, in, out) is semidet.
:- mode fold5(
    pred(in, in, out, in, out, in, out, in, out, mdi, muo) is semidet, in,
    in, out, in, out, in, out, in, out, mdi, muo) is semidet.
:- mode fold5(
    pred(in, in, out, in, out, in, out, in, out, di, uo) is semidet, in,
    in, out, in, out, in, out, in, out, di, uo) is semidet.

:- pred fold6(
    pred(T1, T2, T2, T3, T3, T4, T4, T5, T5, T6, T6, T7, T7),
    set_unordlist(T1), T2, T2, T3, T3, T4, T4, T5, T5, T6, T6, T7, T7).
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

    % all_true(Pred, Set) succeeds iff Pred(Element) succeeds for all the
    % elements of Set.
    %
:- pred all_true(pred(T)::in(pred(in) is semidet),
    set_unordlist(T)::in) is semidet.

    % Return the set of items for which the predicate succeeds.
    %
:- pred filter(pred(T)::in(pred(in) is semidet),
    set_unordlist(T)::in, set_unordlist(T)::out) is det.

    % Return the set of items for which the predicate succeeds,
    % and the set for which it fails.
    %
:- pred filter(pred(T)::in(pred(in) is semidet),
    set_unordlist(T)::in, set_unordlist(T)::out, set_unordlist(T)::out) is det.

    % divide(Pred, Set, TruePart, FalsePart):
    % TruePart consists of those elements of Set for which Pred succeeds;
    % FalsePart consists of those elements of Set for which Pred fails.
    % NOTE: this is the same as filter/4.
    %
:- pred divide(pred(T)::in(pred(in) is semidet),
    set_unordlist(T)::in, set_unordlist(T)::out, set_unordlist(T)::out) is det.

%--------------------------------------------------------------------------%
%--------------------------------------------------------------------------%

:- implementation.

%--------------------------------------------------------------------------%

:- type set_unordlist(T)
    --->    sul(list(T)).

set_unordlist.list_to_set(List, sul(List)).

set_unordlist.from_list(List) = sul(List).

set_unordlist.sorted_list_to_set(List, sul(List)).

set_unordlist.from_sorted_list(List) = sul(List).

set_unordlist.to_sorted_list(sul(Set), List) :-
    list.sort_and_remove_dups(Set, List).

set_unordlist.insert_list(List, sul(!.Set), sul(!:Set)) :-
    list.append(List, !Set).

set_unordlist.insert(E, sul(S0), sul([E | S0])).

set_unordlist.insert_new(E, sul(S0), sul(S)) :-
    ( list.member(E, S0) ->
        fail
    ;
        S = [E | S0]
    ).

set_unordlist.init(sul([])).

:- pragma promise_equivalent_clauses(set_unordlist.singleton_set/2).

set_unordlist.singleton_set(X::in, Set::out) :-
    Set = sul([X]).

set_unordlist.singleton_set(X::in, Set::in) :-
    Set = sul(Xs),
    list.sort_and_remove_dups(Xs, [X]).

set_unordlist.singleton_set(X::out, Set::in) :-
    Set = sul(Xs),
    list.sort_and_remove_dups(Xs, [X]).

set_unordlist.is_singleton(sul(Xs), X) :-
    list.sort_and_remove_dups(Xs, [X]).

set_unordlist.equal(SetA, SetB) :-
    set_unordlist.subset(SetA, SetB),
    set_unordlist.subset(SetB, SetA).

set_unordlist.empty(sul([])).

set_unordlist.is_empty(sul([])).

set_unordlist.non_empty(sul([_ | _])).

set_unordlist.subset(sul([]), _).
set_unordlist.subset(sul([E | S0]), S1) :-
    set_unordlist.member(E, S1),
    set_unordlist.subset(sul(S0), S1).

set_unordlist.superset(S0, S1) :-
    set_unordlist.subset(S1, S0).

set_unordlist.member(E, sul(S)) :-
    list.member(E, S).

set_unordlist.is_member(E, S, R) :-
    ( set_unordlist.member(E, S) ->
        R = yes
    ;
        R = no
    ).

set_unordlist.contains(S, E) :-
    set_unordlist.member(E, S).

set_unordlist.delete_list([], !S).
set_unordlist.delete_list([X | Xs], !S) :-
    set_unordlist.delete(X, !S),
    set_unordlist.delete_list(Xs, !S).

set_unordlist.delete(E, sul(!.S), sul(!:S)) :-
    list.delete_all(!.S, E, !:S).

set_unordlist.remove_list([], !S).
set_unordlist.remove_list([X | Xs], !S) :-
    set_unordlist.remove(X, !S),
    set_unordlist.remove_list(Xs, !S).

set_unordlist.remove(E, sul(S0), sul(S)) :-
    list.member(E, S0),
    set_unordlist.delete(E, sul(S0), sul(S)).

set_unordlist.remove_least(E, Set0, sul(Set)) :-
    Set0 = sul([_ | _]),   % Fail early on an empty set.
    set_unordlist.to_sorted_list(Set0, [E | Set]).

set_unordlist.union(sul(Set0), sul(Set1), sul(Set)) :-
    list.append(Set1, Set0, Set).

set_unordlist.union_list(LS) = S :-
    set_unordlist.power_union(sul(LS), S).

set_unordlist.power_union(sul(PS), sul(S)) :-
    set_unordlist.init(S0),
    set_unordlist.power_union_2(PS, S0, sul(S1)),
    list.sort_and_remove_dups(S1, S).

:- pred set_unordlist.power_union_2(list(set_unordlist(T))::in,
    set_unordlist(T)::in, set_unordlist(T)::out) is det.

set_unordlist.power_union_2([], !S).
set_unordlist.power_union_2([T | Ts], !S) :-
    set_unordlist.union(!.S, T, !:S),
    set_unordlist.power_union_2(Ts, !S).

set_unordlist.intersect(sul(S0), sul(S1), sul(S)) :-
    set_unordlist.intersect_2(S0, S1, [], S).

:- pred set_unordlist.intersect_2(list(T)::in, list(T)::in,
    list(T)::in, list(T)::out) is det.

set_unordlist.intersect_2([], _, S, S).
set_unordlist.intersect_2([E | S0], S1, S2, S) :-
    ( list.member(E, S1) ->
        S3 = [E | S2]
    ;
        S3 = S2
    ),
    set_unordlist.intersect_2(S0, S1, S3, S).

set_unordlist.power_intersect(sul([]), sul([])).
set_unordlist.power_intersect(sul([S0 | Ss]), S) :-
    (
        Ss = [],
        S = S0
    ;
        Ss = [_ | _],
        set_unordlist.power_intersect(sul(Ss), S1),
        set_unordlist.intersect(S1, S0, S)
    ).

set_unordlist.intersect_list(Sets) =
    set_unordlist.power_intersect(sul(Sets)).

%--------------------------------------------------------------------------%

set_unordlist.difference(A, B, C) :-
    set_unordlist.difference_2(B, A, C).

:- pred set_unordlist.difference_2(set_unordlist(T)::in, set_unordlist(T)::in,
    set_unordlist(T)::out) is det.

set_unordlist.difference_2(sul([]), C, C).
set_unordlist.difference_2(sul([E | Es]), A, C) :-
    set_unordlist.delete(E, A, B),
    set_unordlist.difference_2(sul(Es), B, C).

%-----------------------------------------------------------------------------%

set_unordlist.count(Set) = Count :-
    set_unordlist.count(Set, Count).

set_unordlist.count(sul(Set), Count) :-
    list.remove_dups(Set, Elems),
    list.length(Elems, Count).

%-----------------------------------------------------------------------------%

set_unordlist.fold(F, S, A) = B :-
    B = list.foldl(F, set_unordlist.to_sorted_list(S), A).

set_unordlist.fold(P, S, !A) :-
    list.foldl(P, set_unordlist.to_sorted_list(S), !A).

set_unordlist.fold2(P, S, !A, !B) :-
    list.foldl2(P, set_unordlist.to_sorted_list(S), !A, !B).

set_unordlist.fold3(P, S, !A, !B, !C) :-
    list.foldl3(P, set_unordlist.to_sorted_list(S), !A, !B, !C).

set_unordlist.fold4(P, S, !A, !B, !C, !D) :-
    list.foldl4(P, set_unordlist.to_sorted_list(S), !A, !B, !C, !D).

set_unordlist.fold5(P, S, !A, !B, !C, !D, !E) :-
    list.foldl5(P, set_unordlist.to_sorted_list(S), !A, !B, !C, !D, !E).

set_unordlist.fold6(P, S, !A, !B, !C, !D, !E, !F) :-
    list.foldl6(P, set_unordlist.to_sorted_list(S), !A, !B, !C, !D, !E, !F).

%-----------------------------------------------------------------------------%

set_unordlist.all_true(P, sul(L)) :-
    list.all_true(P, L).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
% Ralph Becket <rwab1@cam.sri.com> 24/04/99
%   Function forms added.

set_unordlist.list_to_set(Xs) = S :-
    set_unordlist.list_to_set(Xs, S).

set_unordlist.sorted_list_to_set(Xs) = S :-
    set_unordlist.sorted_list_to_set(Xs, S).

set_unordlist.to_sorted_list(S) = Xs :-
    set_unordlist.to_sorted_list(S, Xs).

set_unordlist.init = S :-
    set_unordlist.init(S).

set_unordlist.make_singleton_set(T) = S :-
    set_unordlist.singleton_set(T, S).

set_unordlist.insert(!.S, T) = !:S :-
    set_unordlist.insert(T, !S).

set_unordlist.insert_list(!.S, Xs) = !:S :-
    set_unordlist.insert_list(Xs, !S).

set_unordlist.delete(!.S, T) = !:S :-
    set_unordlist.delete(T, !S).

set_unordlist.delete_list(!.S, Xs) = !:S :-
    set_unordlist.delete_list(Xs, !S).

set_unordlist.union(S1, S2) = S3 :-
    set_unordlist.union(S1, S2, S3).

set_unordlist.power_union(SS) = S :-
    set_unordlist.power_union(SS, S).

set_unordlist.intersect(S1, S2) = S3 :-
    set_unordlist.intersect(S1, S2, S3).

set_unordlist.power_intersect(SS) = S :-
    set_unordlist.power_intersect(SS, S).

set_unordlist.difference(S1, S2) = S3 :-
    set_unordlist.difference(S1, S2, S3).

set_unordlist.map(F, S1) = S2 :-
    S2 = set_unordlist.list_to_set(list.map(F,
        set_unordlist.to_sorted_list(S1))).

set_unordlist.filter_map(PF, S1) = S2 :-
    S2 = set_unordlist.list_to_set(list.filter_map(PF,
        set_unordlist.to_sorted_list(S1))).

%-----------------------------------------------------------------------------%

set_unordlist.filter(Pred, Set, TrueSet) :-
    % XXX This should be more efficient.
    set_unordlist.divide(Pred, Set, TrueSet, _FalseSet).

set_unordlist.filter(Pred, Set, TrueSet, FalseSet) :-
    set_unordlist.divide(Pred, Set, TrueSet, FalseSet).

set_unordlist.divide(Pred, sul(Set), sul(RevTruePart), sul(RevFalsePart)) :-
    set_unordlist.divide_2(Pred, Set, [], RevTruePart, [], RevFalsePart).

:- pred set_unordlist.divide_2(pred(T1)::in(pred(in) is semidet),
    list(T1)::in,
    list(T1)::in, list(T1)::out,
    list(T1)::in, list(T1)::out) is det.

set_unordlist.divide_2(_Pred, [], !RevTrue, !RevFalse).
set_unordlist.divide_2(Pred, [H | T], !RevTrue, !RevFalse) :-
    ( Pred(H) ->
        !:RevTrue = [H | !.RevTrue]
    ;
        !:RevFalse = [H | !.RevFalse]
    ),
    set_unordlist.divide_2(Pred, T, !RevTrue, !RevFalse).

%-----------------------------------------------------------------------------%
:- end_module set_unordlist.
%-----------------------------------------------------------------------------%
