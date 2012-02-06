%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : - (from VoDKA project)
%%%-----------------------------------------------------------------------------

-module(storage.util.proplist).

-import(lists).
-import(storage.util.proplist).


-export([get/2, get/3, get_sure/3, set/3, multi_get/3]).

%%
%%
%%
get(Key, PropList) ->
    case lists:keysearch(Key, 1, PropList) of
        {value, {Key, V}} -> {ok, V};
        _                 -> not_found
    end.

%%
%%
%%
get(Key, Default, PropList) ->
    case lists:keysearch(Key, 1, PropList) of
        {value, {Key, V}} -> V;
        _                 -> Default
    end.

%%
%%
%%
set(Key, Value, PropList) ->
    set(Key, Value, PropList, []).

set(Key, Value, [], PropList) ->
    [{Key,Value} | PropList];
set(Key, Value, [{Key,_}|PropList], Props) ->
    [{Key, Value} | Props ++ PropList];
set(Key, Value, [P|PropList], Props) ->
    set(Key, Value, PropList, [P|Props]).

%%
%%
%%
get_sure(Key, Default, PropList) ->
    case lists:keysearch(Key, 1, PropList) of
        {value, {Key, V}} ->
            {V, PropList};
        _ ->
            {Default, [{Key,Default} | PropList]}
    end.

%%
%%
%%
multi_get([], [], _) ->
    [];
multi_get([Key|Keys], [Default|Defaults], PropList) ->
    [ proplist:get(Key, Default, PropList) | multi_get(Keys, Defaults, PropList) ].
