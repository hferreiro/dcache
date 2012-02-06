-module(storage.util.server).

-import(gen_server).

-include("config.hrl").

-export([
    call/2,
    reentrant_call/2,
    cast/2,
    handle_call/4
        ]).

call(Server, Request) ->
    gen_server:call(Server, Request, ?GENSERVER_TIMEOUT).

reentrant_call(Server, Request) ->
    call(Server, {reentrant, Request}).

cast(Server, Request) ->
    spawn(fun() ->
            call(Server, Request)
          end),
    ok.

handle_call(Module, {reentrant, Request}, {FromPid, _} = From, State) ->
    spawn(fun() ->
            case catch link(FromPid) of
                {'EXIT', _} ->
                    true;
                _ ->
                    {Result, _NewState} = Module:handle_request(Request, State),
                    unlink(FromPid),
                    gen_server:reply(From, Result)
            end
          end),
    {noreply, State};

handle_call(Module, Request, {FromPid, _} = _From, State) ->
    case catch Module:handle_request(Request, State) of
        {'EXIT', Reason} ->
            exit(FromPid, Reason),
            {reply, {error, Reason}, State};
        {Result, NewState} ->
            {reply, Result, NewState}
    end.
