%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : Dummy Data Destination (from VoDKA project)
%%%-----------------------------------------------------------------------------

-module(storage.pipe.dd.dummy).

-include("ds_info.hrl").

-export([init/2, write/2, done/1, abort/1]).

%%%-----------------------------------------------------------------------------
%%% API
%%%-----------------------------------------------------------------------------

%%
%%
%%
init(_, {verbose, N}) ->
    {ok, {verbose, 0, 0, N}};

%%
init(_, quiet) ->
    {ok, quiet}.

%%
%%
%%
write(Data, {verbose, N, T, M}) when N+size(Data) >= M ->
    {ok, {verbose, 0, T+N+size(Data), M}};
write(Data, {verbose, N, T, M}) ->
    {ok, {verbose, N+size(Data), T, M}};
write(_, quiet) ->
    {ok, quiet}.

%%
%%
%%
done({verbose, N, T, M}) when N > 0 ->
    done({verbose, 0, T+N, M});
done({verbose, 0, _, _}) ->
    ok;
done(quiet) ->
    ok.

%%
%%
%%
abort({verbose, N, T, M}) when N > 0 ->
    abort({verbose, 0, T+N, M});
abort({verbose, 0, _, _}) ->
    ok;
abort(quiet) ->
    ok.
