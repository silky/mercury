%---------------------------------------------------------------------------%
% vim: ts=4 sw=4 et tw=0 wm=0 ft=mercury
%---------------------------------------------------------------------------%
% Copyright (C) 1994-1995,1997,1999,2004-2006,2008,2011-2012 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%-----------------------------------------------------------------------------%
% 
% File: bimap.m.
% Main author: conway.
% Stability: medium.
% 
% This file provides a bijective map ADT.
% A map (also known as a dictionary or an associative array) is a collection
% of (Key, Data) pairs which allows you to look up any Data item given the
% Key. A bimap also allows you to efficiently look up the Key given the Data.
% This time efficiency comes at the expense of using twice as much space.
% 
%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- module bimap.
:- interface.

:- import_module assoc_list.
:- import_module list.
:- import_module map.
:- import_module maybe.

%-----------------------------------------------------------------------------%

:- type bimap(K, V).

%-----------------------------------------------------------------------------%

    % Initialize an empty bimap.
    %
:- func init = bimap(K, V).
:- pred init(bimap(K, V)::out) is det.

    % Initialize a bimap with the given key-value pair.
    %
:- func singleton(K, V) = bimap(K, V).

    % Check whether a bimap is empty.
    %
:- pred is_empty(bimap(K, V)::in) is semidet.

    % True if both bimaps have the same set of key-value pairs, regardless of
    % how the bimaps were constructed.
    %
    % Unifying bimaps does not work as one might expect because the internal
    % structures of two bimaps that contain the same set of key-value pairs
    % may be different.
    %
:- pred equal(bimap(K, V)::in, bimap(K, V)::in) is semidet.

    % Search the bimap. The first mode searches for a value given a key
    % and the second mode searches for a key given a value.
    %
:- pred search(bimap(K, V), K, V).
:- mode search(in, in, out) is semidet.
:- mode search(in, out, in) is semidet.

    % Search the bimap for the value corresponding to a given key.
    %
:- func forward_search(bimap(K, V), K) = V is semidet.
:- pred forward_search(bimap(K, V)::in, K::in, V::out) is semidet.

    % Search the bimap for the key corresponding to the given value.
    %
:- func reverse_search(bimap(K, V), V) = K is semidet.
:- pred reverse_search(bimap(K, V)::in, K::out, V::in) is semidet.

    % Look up the value in the bimap corresponding to the given key.
    % Throws an exception if the key is not present in the bimap.
    %
:- func lookup(bimap(K, V), K) = V.
:- pred lookup(bimap(K, V)::in, K::in, V::out) is det.

    % Look up the key in the bimap corresponding to the given value.
    % Throws an exception if the value is not present in the bimap.
    %
:- func reverse_lookup(bimap(K, V), V) = K.
:- pred reverse_lookup(bimap(K, V)::in, K::out, V::in) is det.

    % Given a bimap, return a list of all the keys in the bimap.
    %
:- func ordinates(bimap(K, V)) = list(K).
:- pred ordinates(bimap(K, V)::in, list(K)::out) is det.

    % Given a bimap, return a list of all the data values in the bimap.
    %
:- func coordinates(bimap(K, V)) = list(V).
:- pred coordinates(bimap(K, V)::in, list(V)::out) is det.

    % Succeeds iff the bimap contains the given key.
    %
:- pred contains_key(bimap(K, V)::in, K::in) is semidet.

    % Succeeds iff the bimap contains the given value.
    %
:- pred contains_value(bimap(K, V)::in, V::in) is semidet.

    % Insert a new key-value pair into the bimap.
    % Fails if either the key or value already exists.
    %
:- func insert(bimap(K, V), K, V) = bimap(K, V) is semidet.
:- pred insert(K::in, V::in, bimap(K, V)::in, bimap(K, V)::out)
    is semidet.

    % As above but throws an exception if the key or value already
    % exists.
    %
:- func det_insert(bimap(K, V), K, V) = bimap(K, V).
:- pred det_insert(K::in, V::in, bimap(K, V)::in, bimap(K, V)::out)
    is det.

    % search_insert(K, V, MaybeOldV, !Bimap):
    %
    % Search for the key K in the bimap. If the key is already in the bimap,
    % with corresponding value OldV, set MaybeOldV to yes(OldV). If it
    % is not in the bimap, then insert it with value V. The value of V
    % should be guaranteed to be different to all the values already
    % in !.Bimap. If it isn't, this predicate will abort.
    %
:- pred search_insert(K::in, V::in, maybe(V)::out,
    bimap(K, V)::in, bimap(K, V)::out) is det.

    % Update the key and value if already present, otherwise insert the
    % new key and value.
    %
    % NOTE: setting the key-value pair (K, V) will remove the key-value pairs
    % (K, V1) and (K1, V) if they exist.
    %
:- func set(bimap(K, V), K, V) = bimap(K, V).
:- pred set(K::in, V::in, bimap(K, V)::in, bimap(K, V)::out) is det.

    % Insert key-value pairs from an association list into the given bimap.
    % Fails if the contents of the association list and the initial bimap
    % do not implicitly form a bijection.
    %
:- func insert_from_assoc_list(assoc_list(K, V), bimap(K, V)) =
    bimap(K, V) is semidet.
:- pred insert_from_assoc_list(assoc_list(K, V)::in,
    bimap(K, V)::in, bimap(K, V)::out) is semidet.

    % As above but throws an exception if the association list and
    % initial bimap are not implicitly bijective.
    %
:- func det_insert_from_assoc_list(assoc_list(K, V), bimap(K, V))
    = bimap(K, V).
:- pred det_insert_from_assoc_list(assoc_list(K, V)::in,
    bimap(K, V)::in, bimap(K, V)::out) is det.

    % Insert key-value pairs from a pair of corresponding lists.
    % Throws an exception if the lists are not of equal lengths
    % or if they do not implicitly define a bijection.
    %
:- func det_insert_from_corresponding_lists(list(K), list(V),
    bimap(K, V)) = bimap(K, V).
:- pred det_insert_from_corresponding_lists(list(K)::in, list(V)::in,
    bimap(K, V)::in, bimap(K, V)::out) is det.

    % Apply set to each key-value pair in the association list.
    % The key-value pairs from the association list may update existing keys
    % and values in the bimap.
    %
:- func set_from_assoc_list(assoc_list(K, V), bimap(K, V))
    = bimap(K, V).
:- pred set_from_assoc_list(assoc_list(K, V)::in,
    bimap(K, V)::in, bimap(K, V)::out) is det.

    % As above but with a pair of corresponding lists in place of an
    % association list. Throws an exception if the lists are not of
    % equal length.
    %
:- func set_from_corresponding_lists(list(K), list(V),
    bimap(K, V)) = bimap(K, V).
:- pred set_from_corresponding_lists(list(K)::in, list(V)::in,
    bimap(K, V)::in, bimap(K, V)::out) is det.

    % Delete a key-value pair from a bimap. If the key is not present,
    % leave the bimap unchanged.
    %
:- func delete_key(bimap(K, V), K) = bimap(K, V).
:- pred delete_key(K::in, bimap(K, V)::in, bimap(K, V)::out) is det.

    % Delete a key-value pair from a bimap. If the value is not present,
    % leave the bimap unchanged.
    %
:- func delete_value(bimap(K, V), V) = bimap(K, V).
:- pred delete_value(V::in, bimap(K, V)::in, bimap(K, V)::out) is det.

    % Apply delete_key to a list of keys.
    %
:- func delete_keys(bimap(K, V), list(K)) = bimap(K, V).
:- pred delete_keys(list(K)::in, bimap(K, V)::in, bimap(K, V)::out)
    is det.

    % Apply delete_value to a list of values.
    %
:- func delete_values(bimap(K, V), list(V)) = bimap(K, V).
:- pred delete_values(list(V)::in, bimap(K, V)::in, bimap(K, V)::out)
    is det.

    % overlay(BIMapA, BIMapB, BIMap):
    % Apply map.overlay to the forward maps of BIMapA and BIMapB,
    % and compute the reverse map from the resulting map.
    %
:- func overlay(bimap(K, V), bimap(K, V)) = bimap(K, V).
:- pred overlay(bimap(K, V)::in, bimap(K, V)::in, bimap(K, V)::out)
    is det.

    % Count the number of key-value pairs in the bimap.
    %
:- func count(bimap(K, V)) = int.

    % Convert a bimap to an association list.
    %
:- func to_assoc_list(bimap(K, V)) = assoc_list(K, V).
:- pred to_assoc_list(bimap(K, V)::in, assoc_list(K, V)::out) is det.

    % Convert an association list to a bimap. Fails if the association list
    % does not implicitly define a bijection, i.e. a key or value occurs
    % multiple times in the association list.
    %
:- func from_assoc_list(assoc_list(K, V)) = bimap(K, V) is semidet.
:- pred from_assoc_list(assoc_list(K, V)::in, bimap(K, V)::out)
    is semidet.

    % As above but throws an exception instead of failing if the
    % association list does not implicitly define a bijection.
    %
:- func det_from_assoc_list(assoc_list(K, V)) = bimap(K, V).
:- pred det_from_assoc_list(assoc_list(K, V)::in, bimap(K, V)::out)
    is det.

    % Convert a pair of lists into a bimap. Fails if the lists do not
    % implicitly define a bijection or if the lists are of unequal length.
    %
:- func from_corresponding_lists(list(K), list(V)) = bimap(K, V)
    is semidet.
:- pred from_corresponding_lists(list(K)::in, list(V)::in,
    bimap(K, V)::out) is semidet.

    % As above but throws an exception instead of failing if the lists
    % do not implicitly define a bijection or are of unequal length.
    %
:- func det_from_corresponding_lists(list(K), list(V)) = bimap(K, V).
:- pred det_from_corresponding_lists(list(K)::in, list(V)::in,
    bimap(K, V)::out) is det.

:- func apply_forward_map_to_list(bimap(K, V), list(K)) = list(V).
:- pred apply_forward_map_to_list(bimap(K, V)::in, list(K)::in,
    list(V)::out) is det.

:- func apply_reverse_map_to_list(bimap(K, V), list(V)) = list(K).
:- pred apply_reverse_map_to_list(bimap(K, V)::in, list(V)::in,
    list(K)::out) is det.

    % Apply a transformation predicate to all the keys.
    % Throws an exception if the resulting bimap is not bijective.
    %
:- func map_keys(func(V, K) = L, bimap(K, V)) = bimap(L, V).
:- pred map_keys(pred(V, K, L)::in(pred(in, in, out) is det),
    bimap(K, V)::in, bimap(L, V)::out) is det.

    % Apply a transformation predicate to all the values.
    % Throws an exception if the resulting bimap is not bijective.
    %
:- func map_values(func(K, V) = W, bimap(K, V)) = bimap(K, W).
:- pred map_values(pred(K, V, W)::in(pred(in, in, out) is det),
    bimap(K, V)::in, bimap(K, W)::out) is det.

    % Perform an inorder traversal, by key, of the bimap, applying an
    % accumulator predicate for each key-value pair.
    %
:- func foldl(func(K, V, A) = A, bimap(K, V), A) = A.
:- pred foldl(pred(K, V, A, A), bimap(K, V), A, A).
:- mode foldl(pred(in, in, in, out) is det, in, in, out) is det.
:- mode foldl(pred(in, in, mdi, muo) is det, in, mdi, muo) is det.
:- mode foldl(pred(in, in, di, uo) is det, in, di, uo) is det.
:- mode foldl(pred(in, in, in, out) is semidet, in, in, out) is semidet.
:- mode foldl(pred(in, in, mdi, muo) is semidet, in, mdi, muo) is semidet.
:- mode foldl(pred(in, in, di, uo) is semidet, in, di, uo) is semidet.

    % Perform a traversal of the bimap, applying an accumulator predicate
    % with two accumulators for each key-value pair. (Although no more
    % expressive than foldl, this is often a more convenient format,
    % and a little more efficient).
    %
:- pred foldl2(pred(K, V, A, A, B, B), bimap(K, V), A, A, B, B).
:- mode foldl2(pred(in, in, in, out, in, out) is det,
    in, in, out, in, out) is det.
:- mode foldl2(pred(in, in, in, out, mdi, muo) is det,
    in, in, out, mdi, muo) is det.
:- mode foldl2(pred(in, in, in, out, di, uo) is det,
    in, in, out, di, uo) is det.
:- mode foldl2(pred(in, in, di, uo, di, uo) is det,
    in, di, uo, di, uo) is det.
:- mode foldl2(pred(in, in, in, out, in, out) is semidet,
    in, in, out, in, out) is semidet.
:- mode foldl2(pred(in, in, in, out, mdi, muo) is semidet,
    in, in, out, mdi, muo) is semidet.
:- mode foldl2(pred(in, in, in, out, di, uo) is semidet,
    in, in, out, di, uo) is semidet.

    % Perform a traversal of the bimap, applying an accumulator predicate
    % with three accumulators for each key-value pair. (Although no more
    % expressive than foldl, this is often a more convenient format,
    % and a little more efficient).
    %
:- pred foldl3(pred(K, V, A, A, B, B, C, C), bimap(K, V),
    A, A, B, B, C, C).
:- mode foldl3(pred(in, in, in, out, in, out, in, out) is det,
    in, in, out, in, out, in, out) is det.
:- mode foldl3(pred(in, in, in, out, in, out, mdi, muo) is det,
    in, in, out, in, out, mdi, muo) is det.
:- mode foldl3(pred(in, in, in, out, in, out, di, uo) is det,
    in, in, out, in, out, di, uo) is det.
:- mode foldl3(pred(in, in, in, out, di, uo, di, uo) is det,
    in, in, out, di, uo, di, uo) is det.
:- mode foldl3(pred(in, in, di, uo, di, uo, di, uo) is det,
    in, di, uo, di, uo, di, uo) is det.
:- mode foldl3(pred(in, in, in, out, in, out, in, out) is semidet,
    in, in, out, in, out, in, out) is semidet.
:- mode foldl3(pred(in, in, in, out, in, out, mdi, muo) is semidet,
    in, in, out, in, out, mdi, muo) is semidet.
:- mode foldl3(pred(in, in, in, out, in, out, di, uo) is semidet,
    in, in, out, in, out, di, uo) is semidet.

    % Extract a the forward map from the bimap, the map from key to value.
    %
:- func forward_map(bimap(K, V)) = map(K, V).

    % Extract the reverse map from the bimap, the map from value to key.
    %
:- func reverse_map(bimap(K, V)) = map(V, K).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module pair.
:- import_module require.

:- type bimap(K, V)
    --->    bimap(map(K, V), map(V, K)).

%-----------------------------------------------------------------------------%

bimap.init = BM :-
    bimap.init(BM).

bimap.init(B) :-
    map.init(Forward),
    map.init(Reverse),
    B = bimap(Forward, Reverse).

bimap.singleton(K, V) = B:-
    Forward = map.singleton(K, V),
    Reverse = map.singleton(V, K),
    B = bimap(Forward, Reverse).

bimap.is_empty(bimap(Forward, _)) :-
    map.is_empty(Forward). % by inference == map.is_empty(Reverse).

bimap.equal(BMA, BMB) :-
    BMA = bimap(ForwardA, _ReverseA),
    BMB = bimap(ForwardB, _ReverseB),
    map.equal(ForwardA, ForwardB).

bimap.search(bimap(Forward, Reverse), K, V) :-
    map.search(Forward, K, V),
    map.search(Reverse, V, K).

bimap.forward_search(BM, K) = V :-
    bimap.forward_search(BM, K, V).

bimap.forward_search(bimap(Forward, _), K, V) :-
    map.search(Forward, K, V).

bimap.reverse_search(BM, V) = K :-
    bimap.reverse_search(BM, K, V).

bimap.reverse_search(bimap(_, Reverse), K, V) :-
    map.search(Reverse, V, K).

bimap.contains_key(bimap(Forward, _), K) :-
    map.contains(Forward, K).

bimap.contains_value(bimap(_, Reverse), V) :-
    map.contains(Reverse, V).

bimap.lookup(BM, K) = V :-
    bimap.lookup(BM, K, V).

bimap.lookup(bimap(Forward, _), K, V) :-
    map.lookup(Forward, K, V).

bimap.reverse_lookup(BM, V) = K :-
    bimap.reverse_lookup(BM, K, V).

bimap.reverse_lookup(bimap(_, Reverse), K, V) :-
    map.lookup(Reverse, V, K).

bimap.ordinates(BM) = Ks :-
    bimap.ordinates(BM, Ks).

bimap.ordinates(bimap(Forward, _), Os) :-
    map.keys(Forward, Os).

bimap.coordinates(BM) = Vs :-
    bimap.coordinates(BM, Vs).

bimap.coordinates(bimap(_, Reverse), Cs) :-
    map.keys(Reverse, Cs).

bimap.insert(!.BM, K, V) = !:BM :-
    bimap.insert(K, V, !BM).

bimap.insert(K, V, bimap(!.Forward, !.Reverse), bimap(!:Forward, !:Reverse)) :-
    map.insert(K, V, !Forward),
    map.insert(V, K, !Reverse).

bimap.det_insert(!.BM, K, V) = !:BM :-
    bimap.det_insert(K, V, !BM).

bimap.det_insert(K, V, !Bimap) :-
    !.Bimap = bimap(Forward0, Reverse0),
    map.det_insert(K, V, Forward0, Forward),
    map.det_insert(V, K, Reverse0, Reverse),
    !:Bimap = bimap(Forward, Reverse).

bimap.search_insert(K, V, MaybeOldV, !Bimap) :-
    !.Bimap = bimap(Forward0, Reverse0),
    map.search_insert(K, V, MaybeOldV, Forward0, Forward),
    (
        MaybeOldV = yes(_)
        % No insertion or any other modification takes place in this case;
        % leave !Bimap alone.
    ;
        MaybeOldV = no,
        % We just inserted K->V into Forward, so now we insert V->K into
        % Reverse.
        map.det_insert(V, K, Reverse0, Reverse),
        !:Bimap = bimap(Forward, Reverse)
    ).

bimap.set(!.BM, K, V) = !:BM :-
    bimap.set(K, V, !BM).

bimap.set(K, V, bimap(!.Forward, !.Reverse), bimap(!:Forward, !:Reverse)) :-
    ( map.search(!.Forward, K, KVal) ->
        ( V \= KVal ->
            map.det_update(K, V, !Forward),
            map.delete(KVal, !Reverse)
        ;
            true
        )
    ;
        map.det_insert(K, V, !Forward)
    ),
    ( map.search(!.Reverse, V, VKey) ->
        ( K \= VKey ->
            map.det_update(V, K, !Reverse),
            map.delete(VKey, !Forward)
        ;
            true
        )
    ;
        map.det_insert(V, K, !Reverse)
    ).

bimap.insert_from_assoc_list(List, BM0) = BM :-
    bimap.insert_from_assoc_list(List, BM0, BM).

bimap.insert_from_assoc_list([], !BM).
bimap.insert_from_assoc_list([ Key - Value | KeyValues], !BM) :-
    bimap.insert(Key, Value, !BM),
    bimap.insert_from_assoc_list(KeyValues, !BM).

bimap.det_insert_from_assoc_list(KVs, !.BM) = !:BM :-
    bimap.det_insert_from_assoc_list(KVs, !BM).

bimap.det_insert_from_assoc_list([], !BM).
bimap.det_insert_from_assoc_list([Key - Value | KeysValues], !BM) :-
    bimap.det_insert(Key, Value, !BM),
    bimap.det_insert_from_assoc_list(KeysValues, !BM).

bimap.det_insert_from_corresponding_lists(Ks, Vs, !.BM) = !:BM :-
    bimap.det_insert_from_corresponding_lists(Ks, Vs, !BM).

bimap.det_insert_from_corresponding_lists([], [], !BM).
bimap.det_insert_from_corresponding_lists([], [_ | _], !BM) :-
    error("bimap.det_insert_from_corresponding_lists: length mismatch").
bimap.det_insert_from_corresponding_lists([_ | _], [], !BM) :-
    error("bimap.det_insert_from_corresponding_lists: length mismatch").
bimap.det_insert_from_corresponding_lists([Key | Keys], [Value | Values],
        !BM) :-
    bimap.det_insert(Key, Value, !BM),
    bimap.det_insert_from_corresponding_lists(Keys, Values, !BM).

bimap.set_from_assoc_list(KVs, BM0) = BM :-
    bimap.set_from_assoc_list(KVs, BM0, BM).

bimap.set_from_assoc_list([], !BM).
bimap.set_from_assoc_list([Key - Value | KeysValues], !BM) :-
    bimap.set(Key, Value, !BM),
    bimap.set_from_assoc_list(KeysValues, !BM).

bimap.set_from_corresponding_lists(Ks, Vs, BM0) = BM :-
    bimap.set_from_corresponding_lists(Ks, Vs, BM0, BM).

bimap.set_from_corresponding_lists([], [], !BM).
bimap.set_from_corresponding_lists([], [_ | _], !BM) :-
    error("bimap.set_from_corresponding_lists: length mismatch").
bimap.set_from_corresponding_lists([_ | _], [], !BM) :-
    error("bimap.set_from_corresponding_lists: length mismatch").
bimap.set_from_corresponding_lists([Key | Keys], [Value | Values],
        !BM) :-
    bimap.set(Key, Value, !BM),
    bimap.set_from_corresponding_lists(Keys, Values, !BM).

bimap.delete_key(!.BM, K) = !:BM :-
    bimap.delete_key(K, !BM).

bimap.delete_key(K, !BM) :-
    !.BM = bimap(Forward0, Reverse0),
    ( map.search(Forward0, K, V) ->
        map.delete(K, Forward0, Forward),
        map.delete(V, Reverse0, Reverse),
        !:BM = bimap(Forward, Reverse)
    ;
        true
    ).

bimap.delete_value(!.BM, V) = !:BM :-
    bimap.delete_value(V, !BM).

bimap.delete_value(V, !BM) :-
    !.BM = bimap(Forward0, Reverse0),
    ( map.search(Reverse0, V, K) ->
        map.delete(K, Forward0, Forward),
        map.delete(V, Reverse0, Reverse),
        !:BM = bimap(Forward, Reverse)
    ;
        true
    ).

bimap.delete_keys(BM0, Ks) = BM :-
    bimap.delete_keys(Ks, BM0, BM).

bimap.delete_keys([], !BM).
bimap.delete_keys([Key | Keys], !BM) :-
    bimap.delete_key(Key, !BM),
    bimap.delete_keys(Keys, !BM).

bimap.delete_values(BM0, Vs) = BM :-
    bimap.delete_values(Vs, BM0, BM).

bimap.delete_values([], !BM).
bimap.delete_values([Value | Values], !BM) :-
    bimap.delete_value(Value, !BM),
    bimap.delete_values(Values, !BM).

bimap.overlay(BMA, BMB) = BM :-
    bimap.overlay(BMA, BMB, BM).

bimap.overlay(BMA, BMB, BM) :-
    bimap.to_assoc_list(BMB, KVBs),
    bimap.overlay_2(KVBs, BMA, BM).

:- pred bimap.overlay_2(assoc_list(K, V)::in, bimap(K, V)::in,
    bimap(K, V)::out) is det.

bimap.overlay_2([], !BM).
bimap.overlay_2([Key - Value | KeysValues], !BM) :-
    bimap.set(Key, Value, !BM),
    bimap.overlay_2(KeysValues, !BM).

bimap.count(BM) = Count :-
    BM = bimap(Forward, _),
    Count = map.count(Forward).

bimap.to_assoc_list(BM) = AL :-
    bimap.to_assoc_list(BM, AL).

bimap.to_assoc_list(bimap(Forward, _), L) :-
    map.to_assoc_list(Forward, L).

bimap.from_assoc_list(AL) = BM :-
    bimap.from_assoc_list(AL, BM).

bimap.from_assoc_list(L, Bimap) :-
    bimap.insert_from_assoc_list(L, bimap.init, Bimap).

bimap.det_from_assoc_list(L) = Bimap :-
    bimap.det_from_assoc_list(L, Bimap).

bimap.det_from_assoc_list(L, Bimap) :-
    bimap.det_insert_from_assoc_list(L, bimap.init, Bimap).

bimap.from_corresponding_lists(Ks, Vs) = BM :-
    bimap.from_corresponding_lists(Ks, Vs, BM).

bimap.from_corresponding_lists(Ks, Vs, BM) :-
    assoc_list.from_corresponding_lists(Ks, Vs, L),
    bimap.from_assoc_list(L, BM).

bimap.det_from_corresponding_lists(Ks, Vs) = BM :-
    bimap.det_from_corresponding_lists(Ks, Vs, BM).

bimap.det_from_corresponding_lists(Ks, Vs, BM) :-
    assoc_list.from_corresponding_lists(Ks, Vs, L),
    bimap.det_from_assoc_list(L, BM).

bimap.apply_forward_map_to_list(BM, Ks) = Vs :-
    bimap.apply_forward_map_to_list(BM, Ks, Vs).

bimap.apply_forward_map_to_list(bimap(Forward, _), Ks, Vs) :-
    map.apply_to_list(Ks, Forward, Vs).

bimap.apply_reverse_map_to_list(BM, Vs) = Ks :-
    bimap.apply_reverse_map_to_list(BM, Vs, Ks).

bimap.apply_reverse_map_to_list(bimap(_, Reverse), Vs, Ks) :-
    map.apply_to_list(Vs, Reverse, Ks).

bimap.map_keys(KeyMap, BM0, BM) :-
    bimap.to_assoc_list(BM0, L0),
    bimap.map_keys_2(KeyMap, L0, [], L),
    bimap.det_from_assoc_list(L, BM).

bimap.map_keys(KeyMap, BM0) = BM :-
    bimap.to_assoc_list(BM0, L0),
    bimap.map_keys_func_2(KeyMap, L0, [], L),
    bimap.det_from_assoc_list(L, BM).

bimap.map_values(ValueMap, BM0, BM) :-
    bimap.to_assoc_list(BM0, L0),
    bimap.map_values_2(ValueMap, L0, [], L),
    bimap.det_from_assoc_list(L, BM).

bimap.map_values(ValueMap, BM0) = BM :-
    bimap.to_assoc_list(BM0, L0),
    bimap.map_values_func_2(ValueMap, L0, [], L),
    bimap.det_from_assoc_list(L, BM).

:- pred bimap.map_keys_2(pred(V, K, L)::in(pred(in, in, out) is det),
    assoc_list(K, V)::in, assoc_list(L, V)::in, assoc_list(L, V)::out)
    is det.

bimap.map_keys_2(_KeyMap, [], !List).
bimap.map_keys_2(KeyMap, [Key0 - Value | Tail0], !List) :-
    KeyMap(Value, Key0, Key),
    !:List = [Key - Value | !.List],
    bimap.map_keys_2(KeyMap, Tail0, !List).

:- pred bimap.map_keys_func_2(func(V, K) = L::in(func(in, in) = out is det),
    assoc_list(K, V)::in, assoc_list(L, V)::in, assoc_list(L, V)::out)
    is det.

bimap.map_keys_func_2(_KeyMap, [], !List).
bimap.map_keys_func_2(KeyMap, [Key0 - Value | Tail0], !List) :-
    Key = KeyMap(Value, Key0),
    !:List = [Key - Value | !.List],
    bimap.map_keys_func_2(KeyMap, Tail0, !List).

:- pred bimap.map_values_2(pred(K, V, W)::in(pred(in, in, out) is det),
    assoc_list(K, V)::in, assoc_list(K, W)::in, assoc_list(K, W)::out) is det.

bimap.map_values_2(_ValueMap, [], !List).
bimap.map_values_2(ValueMap, [Key - Value0 | Tail0], !List) :-
    ValueMap(Key, Value0, Value),
    !:List = [Key - Value | !.List],
    bimap.map_values_2(ValueMap, Tail0, !List).

:- pred bimap.map_values_func_2(func(K, V) = W::in(func(in, in) = out is det),
    assoc_list(K, V)::in, assoc_list(K, W)::in, assoc_list(K, W)::out) is det.

bimap.map_values_func_2(_ValueMap, [], !List).
bimap.map_values_func_2(ValueMap, [Key - Value0 | Tail0], !List) :-
    Value = ValueMap(Key, Value0),
    !:List = [Key - Value | !.List],
    bimap.map_values_func_2(ValueMap, Tail0, !List).

bimap.foldl(Func, bimap(Forward, _), List0) =
    map.foldl(Func, Forward, List0).

bimap.foldl(Pred, bimap(Forward, _), !List) :-
    map.foldl(Pred, Forward, !List).

bimap.foldl2(Pred, bimap(Forward, _), !A, !B) :-
    map.foldl2(Pred, Forward, !A, !B).

bimap.foldl3(Pred, bimap(Forward, _), !A, !B, !C) :-
    map.foldl3(Pred, Forward, !A, !B, !C).

bimap.forward_map(bimap(Forward, _)) = Forward.

bimap.reverse_map(bimap(_, Reverse)) = Reverse.

%----------------------------------------------------------------------------%
:- end_module bimap.
%----------------------------------------------------------------------------%
