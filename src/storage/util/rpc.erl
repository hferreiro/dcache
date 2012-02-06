%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : -
%%%-----------------------------------------------------------------------------

-module(storage.util.rpc).

-import(rpc).

-import(storage.util.util).

-export([call/4, call/5, cast/4, node/0, n2l/1]).

%%%-----------------------------------------------------------------------------
%%% API
%%%-----------------------------------------------------------------------------

%%
%%
%%
call(Node, Module, Func, Args) ->
    rpc:call(Node, Module, Func, Args).

%%
%%
%%
call(Node, Module, Func, Args, Timeout) ->
    rpc:call(Node, Module, Func, Args, Timeout).

%%
%%
%%
cast(Node, Module, Func, Args) ->
    rpc:cast(Node, Module, Func, Args).

%%
%%
%%
node() ->
    erlang:node().

%%
%%
%%
n2l(Node) ->
    util:a2l(Node).
