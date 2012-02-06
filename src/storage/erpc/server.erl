%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : -
%%%-----------------------------------------------------------------------------

-module(storage.erpc.server).
-behaviour(gen_server).

-import(gen_server).
-import(gen_tcp).
-import(error_logger).
-import(lists).
-import(io_lib).
-import(erlang).
-import(inet).
-import(storage.util.monitor).
-import(storage.util.config).

-include_lib("kernel/include/inet.hrl").
-include("config.hrl").

-export([start_link/0]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
%% Internal exports
-export([erpc_server/5, worker/4]).

-record(state,{ accept_pid = null,	 % Pid of current acceptor
                port,                    % Sever port
                timeout,                 % KeepAlive Timeout
	        allow      = all,	 % Allowed modules
	        from       = all,	 % Allow connections from IP addresses/hosts
	        secret     = null}).	 % Shared Secret

%%%-----------------------------------------------------------------------------
%%% API
%%%-----------------------------------------------------------------------------

%%
%%
%%
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%%-----------------------------------------------------------------------------
%%% Callback functions from gen_server
%%%-----------------------------------------------------------------------------

%%
%%
%%
init(_) ->
    process_flag(trap_exit, true),
    Port = config:get_parameter(?ERPC_PORT),
    Allow = all,
    From = all,
    Secret = list_to_binary(config:get_parameter(?ERPC_SECRET)),
    Timeout = config:get_parameter(?ERPC_KEEPALIVE_TIMEOUT),
    {ok, #state{ accept_pid = spawn_link(?MODULE, erpc_server, [Port, Timeout, Allow, From, Secret]),
                 port       = Port,
                 timeout    = Timeout,
                 allow      = Allow,
                 from       = From,
                 secret     = Secret }}.

%%
%%
%%
handle_call(_, _, State) ->
    {reply, unknown_request, State}.

%%
%%
%%
handle_cast(_, State) ->
    {noreply, State}.

%%
%%
%%
handle_info({'EXIT', From, _}, #state{ accept_pid = From }=State) ->
    NewState = State#state{ accept_pid = spawn_link(?MODULE, erpc_server, [State#state.port, State#state.timeout, State#state.allow, State#state.from, State#state.secret]) },
    {noreply, NewState};

handle_info(_, State) ->
    {noreply, State}.

%%
%%
%%
terminate(_, _) ->
    ok.

%%
%%
%%
code_change(_, State, _) ->
    {ok, State}.

%%%-----------------------------------------------------------------------------
%%% Loop
%%%-----------------------------------------------------------------------------

%%
%%
%%
erpc_server(Port, Timeout, Allow, From, Secret) ->
    catch unregister(erpc_loop),
    register(erpc_loop, self()),
    process_flag(trap_exit, true),
    do_erpc_server_init(Port, Timeout, Allow, From, Secret),
    ok.

%%
%%
%%
do_erpc_server_init(Port, Timeout, Allow, From, Secret) ->
    case gen_tcp:listen(Port, [binary, {packet, 4}, {active, false}, {reuseaddr, true}]) of
        {ok, LSock} -> 
            monitor:notify(erpc, info, io_lib:format("ERPC server started", [])),
            accept_loop(Timeout, Allow, From, Secret, LSock, []);
        {error, Reason} ->
            exit(Reason)
    end.

%%
%%
%%
accept_loop(Timeout, Allow, From, Secret, LSock, Children) ->
    {ok, Sock} = gen_tcp:accept(LSock),
    NewChildren = case check_host(Sock, From) of
                      true  ->
                          Pid = spawn_link(?MODULE, worker, [Sock, Timeout, Allow, Secret]),
                          close_dead_children([{Pid, Sock} | Children]);
                      false ->
                          catch gen_tcp:close(Sock),
                          close_dead_children(Children)
                          
                  end,
    accept_loop(Timeout, Allow, From, Secret, LSock, NewChildren).

%%
close_dead_children(Children) ->
    receive
        {'EXIT', Pid, _} ->
            case lists:keysearch(Pid, 1, Children) of
	        {value, {Pid, Sock}} ->
                    catch gen_tcp:close(Sock),
                    lists:keydelete(Pid, 1, Children);
	        _ ->
                    exit(kill)
	    end;
	_       -> close_dead_children(Children)
        after 0 -> Children
    end.

%%
%%
%%
worker(Sock, Timeout, Allow, Secret) ->
    process_flag(trap_exit, true),
    worker(Sock, Timeout, Allow, Secret, []).

worker(Sock, Timeout, Allow, Secret, Pids) ->
    receive
        {'EXIT', Pid, _} ->
            worker(Sock, Timeout, Allow, Secret, lists:delete(Pid, Pids))
        after 0 ->
            case gen_tcp:recv(Sock, 0, Timeout) of
                {ok, Packet} ->
                    case catch binary_to_term(Packet) of
                        {Tag, M, F, A, Ref, Checksum} ->
                            case check({M, F, A, Ref}, Secret, Checksum) of
                                true ->
                                    case check_mod(M, F, Allow) of
                                        allow ->
                                            monitor:notify(erpc, vdebug, io_lib:format("RPC exec [~p]: ~p:~p(~p)", [Ref, M, F, A])),
                                            Pid = spawn_link(fun() ->
                                                                 Reply = (catch apply(M, F, A)),
                                                                 case Tag of
                                                                     call -> ok = gen_tcp:send(Sock, term_to_binary({reply, Ref, Reply}));
                                                                     cast -> true
                                                                 end
                                                             end),
                                            worker(Sock, Timeout, Allow, Secret, [Pid | Pids]);
                                        forbid ->
                                            exit(forbidden_module)
                                    end;
                                false ->
                                    exit(bad_packet)
                            end;
                        _ ->
                            exit(bad_packet)
                    end;
                {error, timeout} ->
                    worker(Sock, Timeout, Allow, Secret, Pids);
                {error, _} ->
                    exit(recv_error)
            end
    end.

%%%-----------------------------------------------------------------------------
%%% Internal functions
%%%-----------------------------------------------------------------------------

%%
%%
%%
check(_, false, _) ->
    true;

check(Ref, Secret, Checksum) ->
    Checksum == erlang:md5(concat_binary([term_to_binary(Ref), Secret])).

%%
%% List is a list containing either {M,F} or just M (or all to allow any)
%% If there is a M which matches, it overides any {M, F}
%%
check_mod(_, _, all) ->
    allow;
check_mod(M, F, [{M, F}| _]) ->
    allow;
check_mod(M, _, [M | _]) ->
    allow;
check_mod(M, F, [_ | T]) ->
    check_mod(M, F, T);
check_mod(_, _, []) ->
    forbid.

%%
%%
%%
check_host(_, all) ->
    true;
check_host(Socket, From) ->
    {Hostname, Address} = case inet:peername(Socket) of
			     {ok, {Addr, _}} ->
				 case get_host(Addr) of
				     {ok, Name} ->
					 {short(Name),Addr};
				     error ->
					 {unkown, Addr}
				 end;
			     {error, _} ->
				 {unknown, unknown}
			 end,
    case lists:member(Hostname, From) of
	true ->
	    true;
	false ->
	    case lists:member(Address, From) of
		true ->
		    true;
		false ->
		    error_logger:format("ERPC. Connection attempt from disallowed host: ~p~n", [Hostname]),
		    false
	    end
    end.

%%
%%
%%
get_host(Address) ->
     case inet:gethostbyaddr(Address) of
	 {ok, Hostent} -> {ok, short(Hostent#hostent.h_name)};
	 {error, _}    -> error
     end.

%%
%%
%%
short(Name) ->
    lists:takewhile(fun(X) -> X /= $. end, Name).
