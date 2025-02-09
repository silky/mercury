%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et wm=0 tw=0
%-----------------------------------------------------------------------------%
% Copyright (C) 1997, 1999-2000, 2002-2003, 2005-2006 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%-----------------------------------------------------------------------------%
% 
% File: bt_array.m
% Main author: bromage.
% Stability: medium-low
% 
% This file contains a set of predicates for generating an manipulating a
% bt_array data structure.  This implementation allows O(log n) access and
% update time, and does not require the bt_array to be unique.  If you need
% O(1) access/update time, use the array datatype instead.  (`bt_array' is
% supposed to stand for either "binary tree array" or "backtrackable array".)
% 
% Implementation obscurity: This implementation is biased towards larger
% indices.  The access/update time for a bt_array of size N with index I is
% actually O(log(N-I)).  The reason for this is so that the resize operations
% can be optimised for a (possibly very) common case, and to exploit
% accumulator recursion in some operations.  See the documentation of resize
% and shrink for more details.
% 
%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- module bt_array.
:- interface.
:- import_module list.

:- type bt_array(T).

%-----------------------------------------------------------------------------%

    % make_empty_array(Low, Array) is true iff Array is a
    % bt_array of size zero starting at index Low.
    %
:- pred make_empty_array(int::in, bt_array(T)::out) is det.
:- func make_empty_array(int) = bt_array(T).

    % init(Low, High, Init, Array) is true iff Array is a
    % bt_array with bounds from Low to High whose elements each equal Init.
    %
:- pred init(int::in, int::in, T::in, bt_array(T)::out) is det.
:- func init(int, int, T) = bt_array(T).

%-----------------------------------------------------------------------------%

    % Returns the lower bound of the array.
    %
:- pred min(bt_array(_T)::in, int::out) is det.
:- func min(bt_array(_T)) = int.

    % Returns the upper bound of the array.
    %
:- pred max(bt_array(_T)::in, int::out) is det.
:- func max(bt_array(_T)) = int.

    % Returns the length of the array,
    % i.e. upper bound - lower bound + 1.
    %
:- pred size(bt_array(_T)::in, int::out) is det.
:- func size(bt_array(_T)) = int.

    % bounds returns the upper and lower bounds of a bt_array.
    %
:- pred bounds(bt_array(_T)::in, int::out, int::out) is det.

    % in_bounds checks whether an index is in the bounds
    % of a bt_array.
    %
:- pred in_bounds(bt_array(_T)::in, int::in) is semidet.

%-----------------------------------------------------------------------------%

    % lookup returns the Nth element of a bt_array.
    % It is an error if the index is out of bounds.
    %
:- pred lookup(bt_array(T)::in, int::in, T::out) is det.
:- func lookup(bt_array(T), int) = T.

    % semidet_lookup is like lookup except that it fails if the index is out of
    % bounds.
    %
:- pred semidet_lookup(bt_array(T)::in, int::in, T::out) is semidet.

    % set sets the nth element of a bt_array, and returns the resulting
    % bt_array. It is an error if the index is out of bounds.
    %
:- pred set(bt_array(T)::in, int::in, T::in, bt_array(T)::out) is det.
:- func set(bt_array(T), int, T) = bt_array(T).

    % set sets the nth element of a bt_array, and returns the
    % resulting bt_array (good opportunity for destructive update ;-).
    % It fails if the index is out of bounds.
    %
:- pred semidet_set(bt_array(T)::in, int::in, T::in, bt_array(T)::out)
    is semidet.

    % `resize(BtArray0, Lo, Hi, Item, BtArray)' is true if BtArray
    % is a bt_array created by expanding or shrinking BtArray0 to fit the
    % bounds (Lo, Hi). If the new bounds are not wholly contained within
    % the bounds of BtArray0, Item is used to fill out the other places.
    %
    % Note: This operation is optimised for the case where the lower bound
    % of the new bt_array is the same as that of the old bt_array. In that
    % case, the operation takes time proportional to the absolute difference
    % in size between the two bt_arrays. If this is not the case, it may take
    % time proportional to the larger of the two bt_arrays.
    %
:- pred resize(bt_array(T)::in, int::in, int::in, T::in,
    bt_array(T)::out) is det.
:- func resize(bt_array(T), int, int, T) = bt_array(T).

    % shrink(BtArray0, Lo, Hi, Item, BtArray) is true if BtArray
    % is a bt_array created by shrinking BtArray0 to fit the bounds (Lo, Hi).
    % It is an error if the new bounds are not wholly within the bounds of
    % BtArray0.
    %
    % Note: This operation is optimised for the case where the lower bound
    % of the new bt_array is the same as that of the old bt_array. In that
    % case, the operation takes time proportional to the absolute difference
    % in size between the two bt_arrays. If this is not the case, it may take
    % time proportional to the larger of the two bt_arrays.
    %
:- pred shrink(bt_array(T)::in, int::in, int::in, bt_array(T)::out)
    is det.
:- func shrink(bt_array(T), int, int) = bt_array(T).

    % from_list(Low, List, BtArray) takes a list (of possibly zero
    % length), and returns a bt_array containing % those elements in the same
    % order that they occurred in the list. The lower bound of the new array
    % is `Low'.
:- pred from_list(int::in, list(T)::in, bt_array(T)::out) is det.
:- func from_list(int, list(T)) = bt_array(T).

    % to_list takes a bt_array and returns a list containing
    % the elements of the bt_array in the same order that they occurred
    % in the bt_array.
    %
:- pred to_list(bt_array(T)::in, list(T)::out) is det.
:- func to_list(bt_array(T)) = list(T).

    % fetch_items takes a bt_array and a lower and upper index,
    % and places those items in the bt_array between these indices into a list.
    % It is an error if either index is out of bounds.
    %
:- pred fetch_items(bt_array(T)::in, int::in, int::in, list(T)::out)
    is det.
:- func fetch_items(bt_array(T), int, int) = list(T).

    % bsearch takes a bt_array, an element to be matched and a
    % comparison predicate and returns the position of the first occurrence
    % in the bt_array of an element which is equivalent to the given one
    % in the ordering provided. Assumes the bt_array is sorted according
    % to this ordering. Fails if the element is not present.
    %
:- pred bsearch(bt_array(T)::in, T::in,
    comparison_pred(T)::in(comparison_pred), int::out) is semidet.

    % Field selection for arrays.
    % Array ^ elem(Index) = lookup(Array, Index).
    %
:- func elem(int, bt_array(T)) = T.

    % Field update for arrays.
    % (Array ^ elem(Index) := Value) = set(Array, Index, Value).
    %
:- func 'elem :='(int, bt_array(T), T) = bt_array(T).

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module int.
:- import_module require.
:- import_module string.

:- type bt_array(T)
    --->    bt_array(int, int, ra_list(T)).

%-----------------------------------------------------------------------------%

make_empty_array(Low, bt_array(Low, High, ListOut)) :-
    High = Low - 1,
    ra_list_nil(ListOut).

init(Low, High, Item, bt_array(Low, High, ListOut)) :-
    ra_list_nil(ListIn),
    ElemsToAdd = High - Low + 1,
    add_elements(ElemsToAdd, Item, ListIn, ListOut).

:- pred add_elements(int::in, T::in, ra_list(T)::in, ra_list(T)::out) is det.

add_elements(ElemsToAdd, Item, RaList0, RaList) :-
    ( ElemsToAdd =< 0 ->
        RaList0 = RaList
    ;
        ra_list_cons(Item, RaList0, RaList1),
        ElemsToAdd1 = ElemsToAdd - 1,
        add_elements(ElemsToAdd1, Item, RaList1, RaList)
    ).

%-----------------------------------------------------------------------------%

min(bt_array(Low, _, _), Low).

max(bt_array(_, High, _), High).

size(bt_array(Low, High, _), Size) :-
    Size = High - Low + 1.

bounds(bt_array(Low, High, _), Low, High).

in_bounds(bt_array(Low, High, _), Index) :-
    Low =< Index, Index =< High.

%-----------------------------------------------------------------------------%

:- pragma inline(actual_position/4).
:- pred actual_position(int::in, int::in, int::in, int::out) is det.

actual_position(Low, High, Index, Pos) :-
    Pos = High - Low - Index.

lookup(bt_array(Low, High, RaList), Index, Item) :-
    actual_position(Low, High, Index, Pos),
    ( ra_list_lookup(Pos, RaList, Item0) ->
        Item = Item0
    ;
        error("bt_array.lookup: Array subscript out of bounds")
    ).

semidet_lookup(bt_array(Low, High, RaList), Index, Item) :-
    actual_position(Low, High, Index, Pos),
    ra_list_lookup(Pos, RaList, Item).

%-----------------------------------------------------------------------------%

set(BtArray0, Index, Item, BtArray) :-
    ( semidet_set(BtArray0, Index, Item, BtArray1) ->
        BtArray = BtArray1
    ;
        error("bt_array.set: index out of bounds")
    ).

semidet_set(bt_array(Low, High, RaListIn), Index, Item,
        bt_array(Low, High, RaListOut)) :-
    actual_position(Low, High, Index, Pos),
    ra_list_update(RaListIn, Pos, Item, RaListOut).

%-----------------------------------------------------------------------------%

resize(Array0, L, H, Item, Array) :-
    Array0 = bt_array(L0, H0, RaList0),
    ( L = L0 ->
        % Optimise the common case where the lower bounds are
        % the same.

        ( H < H0 ->
            SizeDiff = H0 - H,
            ( ra_list_drop(SizeDiff, RaList0, RaList1) ->
                RaList = RaList1
            ;
                error("bt_array.resize: " ++
                    "Can't resize to a less-than-empty array")
            ),
            Array = bt_array(L, H, RaList)
        ; H > H0 ->
            SizeDiff = H - H0,
            add_elements(SizeDiff, Item, RaList0, RaList),
            Array = bt_array(L, H, RaList)
        ;
            Array = Array0
        )
    ;
        int.max(L, L0, L1),
        int.min(H, H0, H1),
        fetch_items(Array0, L1, H1, Items),
        init(L, H, Item, Array1),
        insert_items(Array1, L1, Items, Array)
    ).

shrink(Array0, L, H, Array) :-
    Array0 = bt_array(L0, H0, RaList0),
    ( ( L < L0 ; H > H0 ) ->
        error("bt_array.shrink: New bounds are larger than old ones")
    ; L = L0 ->
        % Optimise the common case where the lower bounds are the same.

        SizeDiff = H0 - H,
        ( ra_list_drop(SizeDiff, RaList0, RaList1) ->
            RaList = RaList1
        ;
            error("bt_array.shrink: Can't resize to a less-than-empty array")
        ),
        Array = bt_array(L, H, RaList)
    ;
        ( ra_list_head(RaList0, Item0) ->
            Item = Item0
        ;
            error("bt_array.shrink: Can't shrink an empty array")
        ),
        int.max(L, L0, L1),
        int.min(H, H0, H1),
        fetch_items(Array0, L1, H1, Items),
        init(L, H, Item, Array1),
        insert_items(Array1, L1, Items, Array)
    ).

%-----------------------------------------------------------------------------%

from_list(Low, List, bt_array(Low, High, RaList)) :-
    list.length(List, Len),
    High = Low + Len - 1,
    ra_list_nil(RaList0),
    reverse_into_ra_list(List, RaList0, RaList).

:- pred reverse_into_ra_list(list(T)::in,
    ra_list(T)::in, ra_list(T)::out) is det.

reverse_into_ra_list([], RaList, RaList).
reverse_into_ra_list([X | Xs], RaList0, RaList) :-
    ra_list_cons(X, RaList0, RaList1),
    reverse_into_ra_list(Xs, RaList1, RaList).

%-----------------------------------------------------------------------------%

:- pred insert_items(bt_array(T)::in, int::in, list(T)::in, bt_array(T)::out)
    is det.

insert_items(Array, _N, [], Array).
insert_items(Array0, N, [Head|Tail], Array) :-
    set(Array0, N, Head, Array1),
    N1 = N + 1,
    insert_items(Array1, N1, Tail, Array).

%-----------------------------------------------------------------------------%

to_list(bt_array(_, _, RaList), List) :-
    reverse_from_ra_list(RaList, [], List).

:- pred reverse_from_ra_list(ra_list(T)::in, list(T)::in, list(T)::out) is det.

reverse_from_ra_list(RaList0, Xs0, Xs) :-
    ( ra_list_head_tail(RaList0, X, RaList1) ->
        reverse_from_ra_list(RaList1, [X | Xs0], Xs)
    ;
        Xs0 = Xs
    ).

%-----------------------------------------------------------------------------%

fetch_items(bt_array(ALow, AHigh, RaList0), Low, High, List) :-
    (
        Low > High
    ->
        List = []
    ;
        actual_position(ALow, AHigh, High, Drop),
        ra_list_drop(Drop, RaList0, RaList),
        Take = High - Low + 1,
        reverse_from_ra_list_count(Take, RaList, [], List0)
    ->
        List = List0
    ;
        List = []
    ).

:- pred reverse_from_ra_list_count(int::in, ra_list(T)::in,
    list(T)::in, list(T)::out) is det.

reverse_from_ra_list_count(I, RaList0, Xs0, Xs) :-
    (
        ra_list_head_tail(RaList0, X, RaList1),
        I >= 0
    ->
        I1 = I - 1,
        reverse_from_ra_list_count(I1, RaList1, [X | Xs0], Xs)
    ;
        Xs0 = Xs
    ).

%-----------------------------------------------------------------------------%

bsearch(A, El, Compare, I) :-
    bounds(A, Lo, Hi),
    Lo =< Hi,
    bsearch_2(A, Lo, Hi, El, Compare, I).

    % XXX Would we gain anything by traversing the ra_list instead
    % of doing a vanilla binary chop?

:- pred bsearch_2(bt_array(T)::in, int::in, int::in, T::in,
    pred(T, T, comparison_result)::in(pred(in, in, out) is det), int::out)
    is semidet.

bsearch_2(A, Lo, Hi, El, Compare, I) :-
    Width = Hi - Lo,

    % If Width < 0, there is no range left.
    Width >= 0,

    % If Width == 0, we may just have found our element.
    % Do a Compare to check.
    ( Width = 0 ->
        lookup(A, Lo, X),
        Compare(El, X, (=)),
        I = Lo
    ;
        % Otherwise find the middle element of the range and check against
        % that. NOTE: We can't use "// 2" because division always rounds
        % towards zero whereas we want the result to be rounded down.
        % (Indices can be negative.)  We could use "div 2", but that's a
        % little more expensive, and we know that we're always dividing
        % by a power of 2. Until such time as we implement strength reduction,
        % the >> 1 stays.

        Mid = (Lo + Hi) >> 1,
        lookup(A, Mid, XMid),
        Compare(XMid, El, Comp),
        ( Comp = (<),
            Mid1 = Mid + 1,
            bsearch_2(A, Mid1, Hi, El, Compare, I)
        ; Comp = (=),
            bsearch_2(A, Lo, Mid, El, Compare, I)
        ; Comp = (>),
            Mid1 = Mid - 1,
            bsearch_2(A, Lo, Mid1, El, Compare, I)
        )
    ).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

% This is a perfect application for submodules, but Mercury didn't have them
% when this was written. :-(

% The heart of the implementation of bt_array is a `random access list'
% or ra_list for short.  It is very similar to a list data type, and
% it supports O(1) head/tail/cons operations, but O(log n) lookup and
% update.  The representation is a list of perfectly balanced binary trees.
%
% For more details on the implementation:
%
%   Chris Okasaki, "Purely Functional Random-Access Lists"
%   Functional Programming Languages and Computer Architecture,
%   June 1995, pp 86-95.

% :- module ra_list.
% :- interface.

% :- type ra_list(T).

:- pred ra_list_nil(ra_list(T)::uo) is det.

:- pred ra_list_cons(T::in, ra_list(T)::in, ra_list(T)::out) is det.

:- pred ra_list_head(ra_list(T)::in, T::out) is semidet.

:- pred ra_list_tail(ra_list(T)::in, ra_list(T)::out) is semidet.

:- pred ra_list_head_tail(ra_list(T)::in, T::out, ra_list(T)::out) is semidet.

%-----------------------------------------------------------------------------%

:- pred ra_list_lookup(int::in, ra_list(T)::in, T::out) is semidet.

:- pred ra_list_update(ra_list(T)::in, int::in, T::in, ra_list(T)::out)
    is semidet.

%-----------------------------------------------------------------------------%

:- pred ra_list_drop(int::in, ra_list(T)::in, ra_list(T)::out) is semidet.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

% :- implementation.

:- type ra_list(T)
    --->    nil
    ;       cons(int, ra_list_bintree(T), ra_list(T)).

:- type ra_list_bintree(T)
    --->    leaf(T)
    ;       node(T, ra_list_bintree(T), ra_list_bintree(T)).

%-----------------------------------------------------------------------------%

:- pragma inline(ra_list_nil/1).

ra_list_nil(nil).

:- pragma inline(ra_list_cons/3).

ra_list_cons(X, List0, List) :-
    (
        List0 = cons(Size1, T1, cons(Size2, T2, Rest)),
        Size1 = Size2
    ->
        NewSize = 1 + Size1 + Size2,
        List = cons(NewSize, node(X, T1, T2), Rest)
    ;
        List = cons(1, leaf(X), List0)
    ).

:- pragma inline(ra_list_head/2).

ra_list_head(cons(_, leaf(X), _), X).
ra_list_head(cons(_, node(X, _, _), _), X).

:- pragma inline(ra_list_tail/2).

ra_list_tail(cons(_, leaf(_), Tail), Tail).
ra_list_tail(cons(Size, node(_, T1, T2), Rest), Tail) :-
    Size2 = Size // 2,
    Tail = cons(Size2, T1, cons(Size2, T2, Rest)).

:- pragma inline(ra_list_head_tail/3).

ra_list_head_tail(cons(_, leaf(X), Tail), X, Tail).
ra_list_head_tail(cons(Size, node(X, T1, T2), Rest), X, Tail) :-
    Size2 = Size // 2,
    Tail = cons(Size2, T1, cons(Size2, T2, Rest)).

%-----------------------------------------------------------------------------%

:- pragma inline(ra_list_lookup/3).

ra_list_lookup(I, List, X) :-
    I >= 0,
    ra_list_lookup_2(I, List, X).

:- pred ra_list_lookup_2(int::in, ra_list(T)::in, T::out) is semidet.

ra_list_lookup_2(I, cons(Size, T, Rest), X) :-
    ( I < Size ->
        ra_list_bintree_lookup(Size, T, I, X)
    ;
        NewI = I - Size,
        ra_list_lookup_2(NewI, Rest, X)
    ).

:- pred ra_list_bintree_lookup(int::in, ra_list_bintree(T)::in, int::in,
    T::out) is semidet.

ra_list_bintree_lookup(_, leaf(X), 0, X).
ra_list_bintree_lookup(Size, node(X0, T1, T2), I, X) :-
    ( I = 0 ->
        X0 = X
    ;
        Size2 = Size // 2,
        ( I =< Size2 ->
            NewI = I - 1,
            ra_list_bintree_lookup(Size2, T1, NewI, X)
        ;
            NewI = I - 1 - Size2,
            ra_list_bintree_lookup(Size2, T2, NewI, X)
        )
    ).

%-----------------------------------------------------------------------------%

:- pragma inline(ra_list_update/4).

ra_list_update(List0, I, X, List) :-
    I >= 0,
    ra_list_update_2(List0, I, X, List).

:- pred ra_list_update_2(ra_list(T)::in, int::in, T::in, ra_list(T)::out)
    is semidet.

ra_list_update_2(cons(Size, T0, Rest), I, X, List) :-
    ( I < Size ->
        ra_list_bintree_update(Size, T0, I, X, T),
        List = cons(Size, T, Rest)
    ;
        NewI = I - Size,
        ra_list_update_2(Rest, NewI, X, List0),
        List = cons(Size, T0, List0)
    ).

:- pred ra_list_bintree_update(int::in, ra_list_bintree(T)::in, int::in, T::in,
    ra_list_bintree(T)::out) is semidet.

ra_list_bintree_update(_, leaf(_), 0, X, leaf(X)).
ra_list_bintree_update(Size, node(X0, T1, T2), I, X, T) :-
    ( I = 0 ->
        T = node(X, T1, T2)
    ;
        Size2 = Size // 2,
        ( I =< Size2 ->
            NewI = I - 1,
            ra_list_bintree_update(Size2, T1, NewI, X, T0),
            T = node(X0, T0, T2)
        ;
            NewI = I - 1 - Size2,
            ra_list_bintree_update(Size2, T2, NewI, X, T0),
            T = node(X0, T1, T0)
        )
    ).

%-----------------------------------------------------------------------------%

ra_list_drop(N, As, Bs) :-
    ( N > 0 ->
        As = cons(Size, _, Cs),
        ( Size < N ->
            N1 = N - Size,
            ra_list_drop(N1, Cs, Bs)
        ;
            ra_list_slow_drop(N, As, Bs)
        )
    ;
        As = Bs
    ).

:- pred ra_list_slow_drop(int::in, ra_list(T)::in, ra_list(T)::out) is semidet.

ra_list_slow_drop(N, As, Bs) :-
    ( N > 0 ->
        N1 = N - 1,
        ra_list_tail(As, Cs),
        ra_list_slow_drop(N1, Cs, Bs)
    ;
        As = Bs
    ).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
% Ralph Becket <rwab1@cl.cam.ac.uk> 29/04/99
%   Function forms added.

make_empty_array(N) = BTA :-
    make_empty_array(N, BTA).

init(N1, N2, T) = BTA :-
    init(N1, N2, T, BTA).

min(BTA) = N :-
    min(BTA, N).

max(BTA) = N :-
    max(BTA, N).

size(BTA) = N :-
    size(BTA, N).

lookup(BTA, N) = T :-
    lookup(BTA, N, T).

set(BT1A, N, T) = BTA2 :-
    set(BT1A, N, T, BTA2).

resize(BT1A, N1, N2, T) = BTA2 :-
    resize(BT1A, N1, N2, T, BTA2).

shrink(BT1A, N1, N2) = BTA2 :-
    shrink(BT1A, N1, N2, BTA2).

from_list(N, Xs) = BTA :-
    from_list(N, Xs, BTA).

to_list(BTA) = Xs :-
    to_list(BTA, Xs).

fetch_items(BTA, N1, N2) = Xs :-
    fetch_items(BTA, N1, N2, Xs).

elem(Index, Array) = lookup(Array, Index).

'elem :='(Index, Array, Value) = set(Array, Index, Value).
