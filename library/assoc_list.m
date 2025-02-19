%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et wm=0 tw=0
%---------------------------------------------------------------------------%
% Copyright (C) 1995-1997, 1999-2001, 2004-2006, 2010-2011 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%---------------------------------------------------------------------------%
% 
% File: assoc_list.m.
% Main authors: fjh, zs.
% Stability: medium to high.
% 
% This file contains the definition of the type assoc_list(K, V)
% and some predicates which operate on those types.
% 
%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- module assoc_list.
:- interface.

:- import_module list.
:- import_module pair.

%-----------------------------------------------------------------------------%

:- type assoc_list(K, V) ==  list(pair(K, V)).

:- type assoc_list(T)   ==  list(pair(T, T)).

    % Swap the two sides of the pairs in each member of the list.
    %
:- func reverse_members(assoc_list(K, V)) = assoc_list(V, K).
:- pred reverse_members(assoc_list(K, V)::in, assoc_list(V, K)::out) is det.

    % Zip together two lists; abort if they are of different lengths.
    %
:- func from_corresponding_lists(list(K), list(V)) = assoc_list(K, V).
:- pred from_corresponding_lists(list(K)::in, list(V)::in, assoc_list(K, V)::out)
    is det.

    % Return the first member of each pair.
    %
:- func keys(assoc_list(K, V)) = list(K).
:- pred keys(assoc_list(K, V)::in, list(K)::out) is det.

    % Return the second member of each pair.
    %
:- func values(assoc_list(K, V)) = list(V).
:- pred values(assoc_list(K, V)::in, list(V)::out) is det.

    % Return the two lists contain respectively the first and second member
    % of each pair in the assoc_list.
    %
:- pred keys_and_values(assoc_list(K, V)::in,
    list(K)::out, list(V)::out) is det.

    % Find the first element of the association list that matches
    % the given key, and return the associated value.
    %
:- pred search(assoc_list(K, V)::in, K::in, V::out) is semidet.

    % An alternative version of search.
    %
:- func assoc_list(K, V) ^ elem(K) = V is semidet.

    % An alternative version of search that throws an exception if the key in
    % question does not appear in the assoc_list.
    %
:- func assoc_list(K, V) ^ det_elem(K) = V is det.

    % Find the first element of the association list that matches the given
    % key. Return the associated value, and the original list with the selected
    % element removed.
    %
:- pred remove(assoc_list(K, V)::in, K::in, V::out, assoc_list(K, V)::out)
    is semidet.

:- func map_keys_only(func(K) = L, assoc_list(K, V)) = assoc_list(L, V).
:- pred map_keys_only(pred(K, L), assoc_list(K, V), assoc_list(L, V)).
:- mode map_keys_only(pred(in, out) is det, in, out) is det.

:- func map_values_only(func(V) = W, assoc_list(K, V)) = assoc_list(K, W).
:- pred map_values_only(pred(V, W), assoc_list(K, V), assoc_list(K, W)).
:- mode map_values_only(pred(in, out) is det, in, out) is det.

:- func map_values(func(K, V) = W, assoc_list(K, V)) = assoc_list(K, W).
:- pred map_values(pred(K, V, W), assoc_list(K, V), assoc_list(K, W)).
:- mode map_values(pred(in, in, out) is det, in, out) is det.

    % filter(Pred, List, TrueList) takes a closure with one
    % input argument and for each member K - V of List X, calls the closure
    % on the key. K - V is included in TrueList iff Pred(K) is true.
    %
:- pred filter(pred(K)::in(pred(in) is semidet),
    assoc_list(K, V)::in, assoc_list(K, V)::out) is det.
:- func filter(pred(K)::in(pred(in) is semidet),
    assoc_list(K, V)::in) = (assoc_list(K, V)::out) is det.

    % negated_filter(Pred, List, FalseList) takes a closure with one
    % input argument and for each member K - V of List X, calls the closure
    % on the key. K - V is included in FalseList iff Pred(K) is false.
    %
:- pred negated_filter(pred(K)::in(pred(in) is semidet),
    assoc_list(K, V)::in, assoc_list(K, V)::out) is det.
:- func negated_filter(pred(K)::in(pred(in) is semidet),
    assoc_list(K, V)::in) = (assoc_list(K, V)::out) is det.

    % filter(Pred, List, TrueList, FalseList) takes a closure with
    % one input argument and for each member K - V of List X, calls the closure
    % on the key. K - V is included in TrueList iff Pred(K) is true.
    % K - V is included in FalseList iff Pred(K) is false.
    %
:- pred filter(pred(K)::in(pred(in) is semidet),
    assoc_list(K, V)::in, assoc_list(K, V)::out, assoc_list(K, V)::out) is det.

    % merge(L1, L2, L):
    %
    % L is the result of merging the elements of L1 and L2, in ascending order.
    % L1 and L2 must be sorted on the keys.
    %
:- pred merge(assoc_list(K, V)::in, assoc_list(K, V)::in,
    assoc_list(K, V)::out) is det.
:- func merge(assoc_list(K, V), assoc_list(K, V)) = assoc_list(K, V).

    % foldl_keys(Pred, List, Start End) calls Pred
    % with each key in List (working left-to-right) and an accumulator
    % (with initial value of Start), and returns the final value in End.
    %
:- pred foldl_keys(pred(K, A, A), assoc_list(K, V), A, A).
:- mode foldl_keys(pred(in, in, out) is det, in, in, out) is det.
:- mode foldl_keys(pred(in, mdi, muo) is det, in, mdi, muo) is det.
:- mode foldl_keys(pred(in, di, uo) is det, in, di, uo) is det.
:- mode foldl_keys(pred(in, in, out) is semidet, in, in, out) is semidet.
:- mode foldl_keys(pred(in, mdi, muo) is semidet, in, mdi, muo) is semidet.
:- mode foldl_keys(pred(in, di, uo) is semidet, in, di, uo) is semidet.
:- mode foldl_keys(pred(in, in, out) is multi, in, in, out) is multi.
:- mode foldl_keys(pred(in, in, out) is nondet, in, in, out) is nondet.

    % foldl_values(Pred, List, Start End) calls Pred
    % with each value in List (working left-to-right) and an accumulator
    % (with initial value of Start), and returns the final value in End.
    %
:- pred foldl_values(pred(V, A, A), assoc_list(K, V), A, A).
:- mode foldl_values(pred(in, in, out) is det, in,
    in, out) is det.
:- mode foldl_values(pred(in, mdi, muo) is det, in,
    mdi, muo) is det.
:- mode foldl_values(pred(in, di, uo) is det, in,
    di, uo) is det.
:- mode foldl_values(pred(in, in, out) is semidet, in,
    in, out) is semidet.
:- mode foldl_values(pred(in, mdi, muo) is semidet, in,
    mdi, muo) is semidet.
:- mode foldl_values(pred(in, di, uo) is semidet, in,
    di, uo) is semidet.
:- mode foldl_values(pred(in, in, out) is multi, in,
    in, out) is multi.
:- mode foldl_values(pred(in, in, out) is nondet, in,
    in, out) is nondet.

    % As above, but with two accumulators.
    %
:- pred foldl2_values(pred(V, A, A, B, B), assoc_list(K, V),
    A, A, B, B).
:- mode foldl2_values(pred(in, in, out, in, out) is det, in,
    in, out, in, out) is det.
:- mode foldl2_values(pred(in, in, out, mdi, muo) is det, in,
    in, out, mdi, muo) is det.
:- mode foldl2_values(pred(in, in, out, di, uo) is det, in,
    in, out, di, uo) is det.
:- mode foldl2_values(pred(in, in, out, in, out) is semidet, in,
    in, out, in, out) is semidet.
:- mode foldl2_values(pred(in, in, out, mdi, muo) is semidet, in,
    in, out, mdi, muo) is semidet.
:- mode foldl2_values(pred(in, in, out, di, uo) is semidet, in,
    in, out, di, uo) is semidet.
:- mode foldl2_values(pred(in, in, out, in, out) is multi, in,
    in, out, in, out) is multi.
:- mode foldl2_values(pred(in, in, out, in, out) is nondet, in,
    in, out, in, out) is nondet.
    
    % As above, but with three accumulators.
    %
:- pred foldl3_values(pred(V, A, A, B, B, C, C), assoc_list(K, V),
    A, A, B, B, C, C).
:- mode foldl3_values(pred(in, in, out, in, out, in, out) is det,
    in, in, out, in, out, in, out) is det.
:- mode foldl3_values(pred(in, in, out, in, out, mdi, muo) is det,
    in, in, out, in, out, mdi, muo) is det.
:- mode foldl3_values(pred(in, in, out, in, out, di, uo) is det,
    in, in, out, in, out, di, uo) is det.
:- mode foldl3_values(pred(in, in, out, in, out, in, out) is semidet,
    in, in, out, in, out, in, out) is semidet.
:- mode foldl3_values(pred(in, in, out, in, out, mdi, muo) is semidet,
    in, in, out, in, out, mdi, muo) is semidet.
:- mode foldl3_values(pred(in, in, out, in, out, di, uo) is semidet,
    in, in, out, in, out, di, uo) is semidet.
:- mode foldl3_values(pred(in, in, out, in, out, in, out) is multi,
    in, in, out, in, out, in, out) is multi.
:- mode foldl3_values(pred(in, in, out, in, out, in, out) is nondet,
    in, in, out, in, out, in, out) is nondet.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module require.
:- import_module string.
:- import_module type_desc.

%-----------------------------------------------------------------------------%

assoc_list.reverse_members(AL1) = AL2 :-
    assoc_list.reverse_members(AL1, AL2).

assoc_list.reverse_members([], []).
assoc_list.reverse_members([K - V | KVs], [V - K | VKs]) :-
    assoc_list.reverse_members(KVs, VKs).

assoc_list.from_corresponding_lists(Ks, Vs) = AL :-
    assoc_list.from_corresponding_lists(Ks, Vs, AL).

assoc_list.from_corresponding_lists(Ks, Vs, KVs) :-
    ( assoc_list.from_corresponding_2(Ks, Vs, KVs0) ->
        KVs = KVs0
    ;
        KeyType = type_name(type_of(Ks)),
        list.length(Ks, KeyLength),
        string.int_to_string(KeyLength, KeyLengthString),
        ValueType = type_name(type_of(Vs)),
        list.length(Vs, ValueLength),
        string.int_to_string(ValueLength, ValueLengthString),
        ErrorString = "assoc_list.from_corresponding_lists: "
            ++ "lists have different lengths.\n"
            ++ "\tKey list type: " ++ KeyType
            ++ "\n\tKey list length: " ++ KeyLengthString
            ++ "\n\tValue list type: " ++ ValueType
            ++ "\n\tValue list length: " ++ ValueLengthString,
        error(ErrorString)
    ).

:- pred assoc_list.from_corresponding_2(list(K)::in, list(V)::in,
    assoc_list(K,V)::out) is semidet.

assoc_list.from_corresponding_2([], [], []).
assoc_list.from_corresponding_2([A | As], [B | Bs], [A - B | ABs]) :-
    assoc_list.from_corresponding_2(As, Bs, ABs).

assoc_list.keys(AL) = Ks :-
    assoc_list.keys(AL, Ks).

assoc_list.keys([], []).
assoc_list.keys([K - _ | KVs], [K | Ks]) :-
    assoc_list.keys(KVs, Ks).

assoc_list.values(AL) = Vs :-
    assoc_list.values(AL, Vs).

assoc_list.values([], []).
assoc_list.values([_ - V | KVs], [V | Vs]) :-
    assoc_list.values(KVs, Vs).

assoc_list.keys_and_values([], [], []).
assoc_list.keys_and_values([K - V | KVs], [K | Ks], [V | Vs]) :-
    assoc_list.keys_and_values(KVs, Ks, Vs).

assoc_list.search([K - V | KVs], Key, Value) :-
    ( K = Key ->
        Value = V
    ;
        assoc_list.search(KVs, Key, Value)
    ).

AL ^ elem(K) = V :-
    assoc_list.search(AL, K, V).

AL ^ det_elem(K) = V :-
    ( if   assoc_list.search(AL, K, V0)
      then V = V0
      else report_lookup_error("assoc_list.det_elem: key not found", K)
    ).

assoc_list.remove([K - V | KVs], Key, Value, Rest) :-
    ( K = Key ->
        Value = V,
        Rest = KVs
    ;
        assoc_list.remove(KVs, Key, Value, Rest1),
        Rest = [K - V | Rest1]
    ).

assoc_list.map_keys_only(_P, [], []).
assoc_list.map_keys_only(P, [K0 - V | KVs0], [K - V | KVs]) :-
    P(K0, K),
    assoc_list.map_keys_only(P, KVs0, KVs).

assoc_list.map_keys_only(_F, []) = [].
assoc_list.map_keys_only(F, [K0 - V | KVs0]) = [K - V | KVs] :-
    K = F(K0),
    KVs = assoc_list.map_keys_only(F, KVs0).

assoc_list.map_values_only(_P, [], []).
assoc_list.map_values_only(P, [K - V0 | KVs0], [K - V | KVs]) :-
    P(V0, V),
    assoc_list.map_values_only(P, KVs0, KVs).

assoc_list.map_values_only(_F, []) = [].
assoc_list.map_values_only(F, [K - V0 | KVs0]) = [K - V | KVs] :-
    V = F(V0),
    KVs = assoc_list.map_values_only(F, KVs0).

assoc_list.map_values(_P, [], []).
assoc_list.map_values(P, [K - V0 | KVs0], [K - V | KVs]) :-
    P(K, V0, V),
    assoc_list.map_values(P, KVs0, KVs).

assoc_list.map_values(_F, []) = [].
assoc_list.map_values(F, [K - V0 | KVs0]) = [K - V | KVs] :-
    V = F(K, V0),
    KVs = assoc_list.map_values(F, KVs0).

assoc_list.filter(_, [],  []).
assoc_list.filter(P, [HK - HV | T], True) :-
    ( P(HK) ->
        assoc_list.filter(P, T, TrueTail),
        True = [HK - HV | TrueTail]
    ;
        assoc_list.filter(P, T, True)
    ).

assoc_list.filter(P, List) = Trues :-
    assoc_list.filter(P, List, Trues).

assoc_list.negated_filter(_, [],  []).
assoc_list.negated_filter(P, [HK - HV | T], False) :-
    ( P(HK) ->
        assoc_list.negated_filter(P, T, False)
    ;
        assoc_list.negated_filter(P, T, FalseTail),
        False = [HK - HV | FalseTail]
    ).

assoc_list.negated_filter(P, List) = Falses :-
    assoc_list.negated_filter(P, List, Falses).

assoc_list.filter(_, [],  [], []).
assoc_list.filter(P, [HK - HV | T], True, False) :-
    ( P(HK) ->
        assoc_list.filter(P, T, TrueTail, False),
        True = [HK - HV | TrueTail]
    ;
        assoc_list.filter(P, T, True, FalseTail),
        False = [HK - HV | FalseTail]
    ).

assoc_list.merge(As, Bs) = ABs :-
    assoc_list.merge(As, Bs, ABs).

assoc_list.merge([], [], []).
assoc_list.merge([A | As], [], [A | As]).
assoc_list.merge([], [B | Bs], [B | Bs]).
assoc_list.merge([A | As], [B | Bs], Cs) :-
    (
        A = AK - _AV,
        B = BK - _BV,
        compare(>, AK, BK)
    ->
        assoc_list.merge([A | As], Bs, Cs0),
        Cs = [B | Cs0]
    ;
        % If compare((=), AK, BK), take A first.
        assoc_list.merge(As, [B | Bs], Cs0),
        Cs = [A | Cs0]
    ).

assoc_list.foldl_keys(_, [], !Acc).
assoc_list.foldl_keys(P, [KV | KVs], !Acc) :-
    KV = K - _V,
    P(K, !Acc),
    assoc_list.foldl_keys(P, KVs, !Acc).

assoc_list.foldl_values(_, [], !Acc).
assoc_list.foldl_values(P, [KV | KVs], !Acc) :-
    KV = _K - V,
    P(V, !Acc),
    assoc_list.foldl_values(P, KVs, !Acc).

assoc_list.foldl2_values(_, [], !Acc1, !Acc2).
assoc_list.foldl2_values(P, [KV | KVs], !Acc1, !Acc2) :-
    KV = _K - V,
    P(V, !Acc1, !Acc2),
    assoc_list.foldl2_values(P, KVs, !Acc1, !Acc2).

assoc_list.foldl3_values(_, [], !Acc1, !Acc2, !Acc3).
assoc_list.foldl3_values(P, [KV | KVs], !Acc1, !Acc2, !Acc3) :-
    KV = _K - V,
    P(V, !Acc1, !Acc2, !Acc3),
    assoc_list.foldl3_values(P, KVs, !Acc1, !Acc2, !Acc3).

%-----------------------------------------------------------------------------%
:- end_module assoc_list.
%-----------------------------------------------------------------------------%
