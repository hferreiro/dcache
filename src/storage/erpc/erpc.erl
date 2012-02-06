%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : -
%%%-----------------------------------------------------------------------------

-module(storage.erpc.erpc).

-import(storage.erpc.client).
-import(storage.util.util).

-export([call/4, call/5, cast/4, node/0, n2l/1]).

%%%-----------------------------------------------------------------------------
%%% API
%%%-----------------------------------------------------------------------------

%%
%%
%%
call(Ip, Module, Func, Args) ->
    client:call(Ip, Module, Func, Args).

%%
%%
%%
call(Ip, Module, Func, Args, Timeout) ->
    client:call(Ip, Module, Func, Args, Timeout).

%%
%%
%%
cast(Ip, Module, Func, Args) ->
    client:cast(Ip, Module, Func, Args).

%%
%%
%%
node() ->
    util:node(ip).

%%
%%
%%
n2l(Ip) ->
    util:ip2l(Ip).
