%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : -
%%%-----------------------------------------------------------------------------

-module(storage.erpc.client).
-behaviour(gen_server).

-import(lists).
-import(erlang).
-import(io).
-import(io_lib).
-import(timer).
-import(gen_server).
-import(gen_tcp).
-import(inet).
-import(lists).
-import(storage.util.monitor).
-import(storage.util.config).
-import(storage.util.util).

-include("config.hrl").

-define(CONNECT_TIMEOUT, 4000).

%% API
-export([start_link/0, call/4, call/5, cast/4, debug/0]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, { port,                % Port
                 sockets = [],        % [{IP, Socket, Timestamp, [Ref]}]
                 blocked = [],        % [{Pid, Ref}]
                 secret  = null }).   % Shared Secret

%%%-----------------------------------------------------------------------------
%%% API
%%%-----------------------------------------------------------------------------

%%
%%
%%
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%
%%
%%
call(Host, Mod, Func, Args) ->
    call(Host, Mod, Func, Args, infinity).

%%
%%
%%
call(Host, Mod, Func, Args, Timeout) ->
    case gen_server:call(?MODULE, {call, Host, Mod, Func, Args}, infinity) of
        {wait, Ref} ->
            case Timeout of
                infinity ->
                    receive
                        {Ref, {'EXIT', Reason}} -> exit(Reason);
                        {Ref, Result}           -> Result
                    end;
                _ ->
                    receive
                        {Ref, {'EXIT', Reason}} -> exit(Reason);
                        {Ref, Result}           -> Result
                        after Timeout           -> {badrpc, timeout}
                    end
            end;
        {badrpc, Reason} ->
            {badrpc, Reason}
    end.

%%
%%
%%
cast(Host, Mod, Func, Args) ->
    gen_server:cast(?MODULE, {cast, Host, Mod, Func, Args}).

%%
%%
%%
debug() ->
    gen_server:call(?MODULE, {debug}).

%%%-----------------------------------------------------------------------------
%%% gen_server interface
%%%-----------------------------------------------------------------------------

%%
%%
%%
init(_) ->
    {ok, #state{ port    = config:get_parameter(?ERPC_PORT),
                 sockets = [],
                 blocked = [],
                 secret  = list_to_binary(config:get_parameter(?ERPC_SECRET)) }}.

%%
%%
%%
handle_call({call, Host, M, F, A}, {Pid, _}, State) ->
    {ok, Result, NewState} = call(State, Host, Pid, M, F, A),
    {reply, Result, NewState};

handle_call({debug}, _, State) ->
    {reply, State, State};

handle_call(_, _, State) ->
    {reply, unknown_request, State}.

%%
%%
%%
handle_cast({cast, Host, M, F, A}, State) ->
    {ok, NewState} = cast(State, Host, M, F, A),
    {noreply, NewState};

handle_cast(_, State) ->
    {noreply, State}.

%%
%%
%%
handle_info({tcp, Socket, Packet}, State) ->
    case catch binary_to_term(Packet) of
        {reply, Ref, Reply} ->
            {ok, NewState} = notify_client(State, Socket, Ref, Reply),
            {noreply, NewState};
        _ ->
            {noreply, State}
    end;

handle_info({tcp_closed, Socket}, State) ->
    {ok, NewState} = remove_socket(State, Socket),
    {noreply, NewState};

handle_info(_, State) ->
    {noreply, State}.

%%
%%
%%
terminate(_, State) ->
    lists:foreach(fun({_, Socket, _, _}) ->
                      catch gen_tcp:close(Socket)
                  end, State#state.sockets),
    lists:foreach(fun({Pid, Ref}) ->
                      Pid ! {Ref, {badrpc, nodedown}}
                  end, State#state.blocked),
    ok.

%%
%%
%%
code_change(_, State, _) ->
    {ok, State}.

%%%-----------------------------------------------------------------------------
%%% Internal implementation
%%%-----------------------------------------------------------------------------

%%
%%
%%
call(State, Host, Pid, M, F, A) ->
    case do_rpc(State, call, Host, Pid, M, F, A) of
        {ok, Ref, NewState}  -> {ok, {wait, Ref}, NewState};
        {error, _}           -> {ok, {badrpc, nodedown}, State};
        {error, _, NewState} -> {ok, {badrpc, nodedown}, NewState}
    end.

%%
%%
%%
cast(State, Host, M, F, A) ->
    case do_rpc(State, cast, Host, none, M, F, A) of
        {ok, NewState}       -> {ok, NewState};
        {error, _}           -> {ok, State};
        {error, _, NewState} -> {ok, NewState}
    end.

%%
%%
%%
do_rpc(State, Tag, Host, Pid, M, F, A) ->
    Ref = now(),
    case inet:getaddr(Host, inet) of
        {ok, Ip} ->
            case lookup_socket(State, Ip) of
                {ok, Socket} ->
                    monitor:notify(erpc, vdebug, io_lib:format("RPC call [~p]: ~p.~p:~p(~p)", [Ref, Host, M, F, A])),
                    case send_cmd(State, Socket, Tag, M, F, A, Ref) of
                        ok              -> add_socket(State, Tag, Socket, Ip, Pid, Ref);
                        {error, Reason} ->
                            case new_socket(State, Ip) of
                                {ok, NewSocket} ->
                                    case send_cmd(State, NewSocket, Tag, M, F, A, Ref) of
                                        ok ->
                                            {ok, NewState} = remove_socket(State, Socket),
                                            add_socket(NewState, Tag, NewSocket, Ip, Pid, Ref);
                                        {error, Reason} ->
                                            {ok, NewState1} = remove_socket(State, Socket),
                                            {ok, NewState2} = remove_socket(NewState1, NewSocket),
                                            {error, Reason, NewState2}
                                    end;
                                {error, Reason} ->
                                    {ok, NewState} = remove_socket(State, Socket),
                                    {error, Reason, NewState}
                            end
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%%
add_socket(State, call, Socket, Ip, Pid, Ref) ->
    case util:keysearch_and_delete(Socket, 2, State#state.sockets) of
        {value, {Ip, Socket, _, Refs}, Sockets} ->
            {ok, Ref,  State#state{ sockets = [{Ip, Socket, now(), [Ref|Refs]} | Sockets],
                                    blocked = [{Pid, Ref} | State#state.blocked] } };
        _ ->
            {ok, Ref,  State#state{ sockets = [{Ip, Socket, now(), [Ref]} | State#state.sockets],
                                    blocked = [{Pid, Ref} | State#state.blocked] } }
    end;

add_socket(State, cast, Socket, Ip, _, _) ->
    case util:keysearch_and_delete(Socket, 2, State#state.sockets) of
        {value, {Ip, Socket, _, Refs}, Sockets} ->
            {ok, State#state{ sockets = [{Ip, Socket, now(), Refs} | Sockets] } };
        _ ->
            {ok, State#state{ sockets = [{Ip, Socket, now(), []} | State#state.sockets] } }
    end.

%%
remove_socket(State, Socket) ->
    case util:keysearch_and_delete(Socket, 2, State#state.sockets) of
        {value, {_, Socket, _, Refs}, Sockets} ->
            catch gen_tcp:close(Socket),
            NewState = lists:foldl(fun(Ref, StateIn) ->
                                       {ok, StateOut} = notify_client(StateIn, Socket, Ref, {badrpc, nodedown}),
                                       StateOut
                                   end, State, Refs),
            {ok, NewState#state{ sockets = Sockets } };
        _ ->
            {ok, State}
    end.

%%
notify_client(State, Socket, Ref, Result) ->
    case util:keysearch_and_delete(Ref, 2, State#state.blocked) of
        {value, {Pid, Ref}, Blocked} ->
            Pid ! {Ref, Result},
            {value, {Ip, Socket, Timestamp, Refs}} = lists:keysearch(Socket, 2, State#state.sockets),
            {ok, State#state{ sockets = lists:keyreplace(Socket, 2, State#state.sockets, {Ip, Socket, Timestamp, [TheRef || TheRef <- Refs, TheRef /= Ref]}),
                              blocked = Blocked }};
        _ ->
            {ok, State}
    end.

%%
lookup_socket(State, Ip) ->
    case lists:keysearch(Ip, 1, State#state.sockets) of
        {value, {Ip, Socket, _, _}} -> {ok, Socket};
        _                           -> new_socket(State, Ip)
    end.

%%
new_socket(State, Ip) ->
    gen_tcp:connect(Ip, State#state.port, [binary, {active, true}, {packet, 4}], ?CONNECT_TIMEOUT).

%%
send_cmd(State, Socket, Tag, M, F, A, Ref) ->
    Packet = term_to_binary( {Tag, M, F, A, Ref, md5({M, F, A, Ref}, State#state.secret)} ),
    gen_tcp:send(Socket, Packet).

%%
md5(Ref, Secret) ->
    erlang:md5(concat_binary([term_to_binary(Ref), Secret])).
