%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : -
%%%-----------------------------------------------------------------------------

-module(storage.rpc).

-import(storage.util.config).
-import(storage.util.util).

-include("config.hrl").

-export([call/4, call/5, cast/4, node/0, n2l/1]).
-export([ecall/4, ecall/5, ecast/4, ecast/5]).

%%%-----------------------------------------------------------------------------
%%% API
%%%-----------------------------------------------------------------------------

%%
%%
%%
call(Node, Module, Func, Args) ->
    (config:get_parameter(?STORAGE_RPC)):call(Node, Module, Func, Args).

%%
%%
%%
call(Node, Module, Func, Args, Timeout) ->
    (config:get_parameter(?STORAGE_RPC)):call(Node, Module, Func, Args, Timeout).

%%
%%
%%
cast(Node, Module, Func, Args) ->
    (config:get_parameter(?STORAGE_RPC)):cast(Node, Module, Func, Args).

%%
%%
%%
node() ->
    (config:get_parameter(?STORAGE_RPC)):node().

%%
%%
%%
n2l(Node) ->
    (config:get_parameter(?STORAGE_RPC)):n2l(Node).

%%%-----------------------------------------------------------------------------
%%% Extended API
%%%-----------------------------------------------------------------------------

%%
%%
%%
ecall(Node, Module, Func, Args) ->
    case call(Node, Module, util:a2a("rpc_" ++ util:a2l(Func)), Args) of
        {badrpc, nodedown} ->
            exit(nodedown);
		{badrpc, {'EXIT', Reason}} ->
            exit(Reason);
        Result ->
            Result
    end.

%%
%%
%%
ecall(State, Node, Module, Func, Args) ->
    case ?MODULE:node() of
        Node ->
            {Result, NewState} = apply(Module, Func, [State | Args]),
            {Result, NewState};
        _ ->
            case call(Node, Module, util:a2a("rpc_" ++ util:a2l(Func)), Args) of
                {badrpc, nodedown} ->
                    exit(nodedown);
				{badrpc, {'EXIT', Reason}} ->
                    exit(Reason);
                Result ->
                    {Result, State}
            end
    end.

%%
%%
%%
ecast(Node, Module, Func, Args) ->
    case cast(Node, Module, util:a2a("rpc_" ++ util:a2l(Func)), Args) of
        {badrpc, Reason} ->
            exit({badrpc, Reason});
        _Result ->
            ok
    end.

%%
%%
%%
ecast(State, Node, Module, Func, Args) ->
    case ?MODULE:node() of
        Node ->
            apply(Module, Func, [State | Args]);
        _ ->
            cast(Node, Module, Func, Args)
    end.
