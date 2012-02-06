%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : -
%%%-----------------------------------------------------------------------------

-module(storage.ring).
-behaviour(gen_server).

-import(gen_server).
-import(gen_tcp).
-import(gen_udp).
-import(io).
-import(lists).
-import(net_adm).
-import(random).
-import(timer).

-import(storage.registry).
-import(storage.util.config).
-import(storage.util.monitor).
-import(storage.util.util).

-include("config.hrl").

%% API
-export([start_link/0, nodes/0, ready/1, neighbor/0]).

%% Internal API
-export([halt/0, snapshot/0, test/4]).
-export([announce/0, server/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, { id,
                 ready         = false,
                 server,
                 port,
                 mode,                  %% bcast | mcast
                 mcast_socket,
                 mcast_ip,
                 mcast_port,
                 bcast_socket,
                 bcast_ip,
                 bcast_port,
                 blocked       = [],     %% [{Pid, Ref}]
                 nodes         = []
               }).

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
nodes() ->
    gen_server:call(?MODULE, {nodes}).

%%
%%
%%
ready(Bool) ->
    gen_server:cast(?MODULE, {ready, Bool}).

%%
%%
%%
neighbor() ->
    do_neighbor(config:get_parameter(?RING_NEIGHBOR_LOOKUP),
                config:get_parameter(?RING_NEIGHBOR_LOOKUP_TIMEOUT)).

%%
do_neighbor([], _) ->
    {error, not_found};

do_neighbor([Mode|Modes], Timeout) ->
    case gen_server:call(?MODULE, {neighbor, Mode, self()}) of
		{wait, Ref} ->
	    	receive
				{Ref, {ok, {error, not_found}}} ->
                    {error, not_found};
				{Ref, {ok, Node}} ->
                    {ok, Node}
            after Timeout ->
                do_neighbor(Modes, Timeout)
	    	end;
        _Else ->
            _Else
    end.

%%%-----------------------------------------------------------------------------
%%% Development API
%%%-----------------------------------------------------------------------------

%%
%%
%%
announce() ->
    gen_server:cast(?MODULE, {announce}).

%%
%%
%%
halt() ->
    lists:foreach(fun(Node) ->
                      case rpc:node() of
                          Node -> true;
                          _    -> rpc:call(Node, erlang, halt, [])
                      end
                  end, ?MODULE:nodes()),
    erlang:halt().

%%
%%
%%
snapshot() ->
    {Graph, Str} = lists:foldl(fun(Node, {G, S}) ->
                                   case catch rpc:call(Node, storage.dstate, snapshot, []) of
                                       {ok, DStateStr} ->
                                           case catch rpc:call(Node, storage.chord, snapshot, [DStateStr]) of
                                               {ok, Graph} ->
                                                   case catch rpc:call(Node, storage.storage, snapshot, []) of
                                                       {ok, StorageStr} ->
                                                           {G ++ "\n" ++ Graph,
                                                            S ++ "\n\n" ++ rpc:n2l(Node) ++ "\n-------------------------------\n" ++ StorageStr};
                                                       _ -> {G, S}
                                                   end;
                                               _ -> {G, S}
                                           end;
                                       _ -> {G, S}
                                   end
                               end, {"", ""}, ?MODULE:nodes()),
    {ok, "digraph ring {\n" ++ Graph ++ "\n" ++ "}", Str}.

%%
%% MOs = int()
%% Concurrency = int()
%% Timeout = int()
%%
test(MOs, Concurrency, Delay, Timeout) ->
    lists:foreach(fun(Node) ->
                      rpc:call(Node, storage.chord, freeze, [ true ])
                  end, ?MODULE:nodes()),
    do_test(MOs, 0, Concurrency, Delay, Timeout).

do_test(0, _, _, _, _) ->
    ok;

do_test(MOs, Round, Concurrency, Delay, Timeout) ->
    FromMO = Round*Concurrency+1,
    ToMO = (Round+1)*Concurrency,
    .io:format("=> Fetching ~w to ~w~n", [FromMO, ToMO]),
    lists:foreach(fun(Node) ->
                      rpc:cast(Node, storage.storage, fetch, [ [ {util:a2a("MO-" ++ util:a2l(MO)), 0} || MO <- lists:seq(FromMO, ToMO) ] ]),
                      receive after Delay -> true end
                  end, util:shake(?MODULE:nodes())),
    receive after Timeout -> true end,
    do_test(MOs-Concurrency, Round+1, Concurrency, Delay, Timeout).


%%%-----------------------------------------------------------------------------
%%% gen_server callbacks
%%%-----------------------------------------------------------------------------

%%
%%
%%
init(_) ->
    monitor:notify(ring, info, "Initializing ring proxy"),
    State0 = #state{ id         = config:get_parameter(?RING_ID),
                     mode       = hd(config:get_parameter(?RING_NEIGHBOR_LOOKUP)),
                     mcast_ip   = config:get_parameter(?RING_MCAST_IP),
                     mcast_port = config:get_parameter(?RING_MCAST_PORT),
                     %bcast
                     bcast_port = config:get_parameter(?RING_BCAST_PORT),
                     port       = config:get_parameter(?RING_PORT) },
	case lists:member(State0#state.mode, [mcast, bcast]) of
        false ->
            Server = nil,
            McastSocket = nil,
            BcastSocket = nil;
        true ->
            Server = spawn_link(?MODULE, server, [self(), config:get_parameter(?RING_PORT)]),
    		{ok, McastSocket} = gen_udp:open(State0#state.mcast_port, [ binary,
                                                                		{active, true},
                                                                		{reuseaddr, true},
                                                                		{multicast_loop, true},
                                                                		{ip, State0#state.mcast_ip},
                                                                		{add_membership, {State0#state.mcast_ip, {0, 0, 0, 0}}},
                                                                		{broadcast, false} ]),
    		{ok, BcastSocket} = gen_udp:open(State0#state.bcast_port, [ binary,
                                                                		{active, true},
                                                                		{reuseaddr, true},
                                                                		{broadcast, true} ])
	end,
    {ok, _} = timer:apply_interval(config:get_parameter(?RING_ANNOUNCE_TIMEOUT), ?MODULE, announce, []),
    {ok, State0#state{ server       = Server,
                       mcast_socket = McastSocket,
                       bcast_socket = BcastSocket,
                       nodes        = [rpc:node()] }}.

%%
%%
%%
handle_call({neighbor, Mode, Pid}, _, State) ->
    {ok, Reply, NewState} = neighbor(State, Mode, Pid),
    {reply, Reply, NewState};

handle_call({nodes}, _, State) ->
    {reply, State#state.nodes, State};

handle_call(_, _, State) ->
    {reply, unknown_request, State}.

%%
%%
%%
handle_cast({ready, Bool}, State) ->
    {noreply, State#state{ ready = Bool}};

handle_cast({announce}, State) ->
    ok = announce_packet(State),
    {noreply, State};

handle_cast(_, State) ->
    {noreply, State}.

%%
%%
%%
handle_info({udp, _, IP, Port, Packet}=_X, #state{ mcast_port = Port } = State) ->
    {ok, NewState} = handle_mcast_packet(State, IP, catch binary_to_term(Packet)),
    {noreply, NewState};

handle_info({server, Packet}, State) ->
    {ok, NewState} = handle_server_packet(State, Packet),
    {noreply, NewState};

handle_info(_, State) ->
    {noreply, State}.

%%
%%
%%
terminate(_, State) ->
    catch gen_udp:close(State#state.bcast_socket),
    catch gen_udp:close(State#state.mcast_socket),
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
neighbor(State, Mode, Pid) ->
    Ref = now(),
    ok = search_neighbor_packet(State, Mode, Ref),
    { ok,
      {wait, Ref},
      State#state{ blocked = [ {Pid, Ref} | State#state.blocked ] } }.

%%
%%
%%
handle_mcast_packet(State, IP, {search_neighbor, RingID, Node, Ref}) when State#state.id == RingID ->
    case rpc:node() of
        Node -> true;
        _    ->
            case State#state.ready of
                true  -> catch neighbor_packet(State, IP, Ref);
                false ->
                    case rpc:node() > Node of
                        true  -> catch neighbor_packet(State, IP, Ref);
                        false -> true
                    end
            end
    end,
    {ok, State};

handle_mcast_packet(State, _, {announce, RingID, Node}) when State#state.id == RingID ->
    case lists:member(Node, State#state.nodes) of
        true  -> {ok, State};
        false -> {ok, State#state{ nodes = [ Node | State#state.nodes] }}
    end;

handle_mcast_packet(State, _, _) ->
    {ok, State}.

%%
%%
%%
handle_server_packet(State, {neighbor, Ref, Node}) ->
    NewBlocked = lists:foldl(fun({Pid, TheRef}, Acc) ->
                                 case TheRef == Ref of
                                     true  -> Pid ! {Ref, {ok, Node}}, Acc;
                                     false -> [{Pid, TheRef} | Acc]
                                 end
                             end, [], State#state.blocked),
    {ok, State#state{ blocked = NewBlocked }};

handle_server_packet(State, _) ->
    {ok, State}.

%%%-----------------------------------------------------------------------------
%%% Packets
%%%-----------------------------------------------------------------------------


%%
%%
%%
announce_packet(#state{ mode = erlang }) ->
    ok = registry:announce(rpc:node()),
    ok;

announce_packet(State) ->
    ok = gen_udp:send(State#state.mcast_socket, State#state.mcast_ip, State#state.mcast_port,
                      term_to_binary({announce, State#state.id, rpc:node()})),
    ok.

%%
%%
%%
search_neighbor_packet(_State, erlang, Ref) ->
    Node = registry:neighbor(rpc:node()),
    self() ! {server, {neighbor, Ref, Node}},
    ok;

search_neighbor_packet(State, bcast, Ref) ->
    ok = gen_udp:send(State#state.bcast_socket, util:node(broadcast), State#state.bcast_port,
                      term_to_binary({search_neighbor, State#state.id, rpc:node(), Ref})),
    ok;

search_neighbor_packet(State, mcast, Ref) ->
    ok = gen_udp:send(State#state.mcast_socket, State#state.mcast_ip, State#state.mcast_port,
                      term_to_binary({search_neighbor, State#state.id, rpc:node(), Ref})),
    ok.

%%
%%
%%
neighbor_packet(State, IP, Ref) ->
    {ok, Socket} = gen_tcp:connect(IP, State#state.port, [binary, {packet, 0}]),
    ok = gen_tcp:send(Socket, term_to_binary({neighbor, Ref, rpc:node()})),
    ok = gen_tcp:close(Socket),
    ok.

%%%-----------------------------------------------------------------------------
%%% Trivial server
%%%-----------------------------------------------------------------------------

%%
%%
%%
server(Pid, Port) ->
    {ok, LSocket} = gen_tcp:listen(Port, [ binary, {active, false}, {packet, 0} ]),
    server_loop(Pid, LSocket).

%%
%%
%%
server_loop(Pid, LSocket) ->
    {ok, Socket} = gen_tcp:accept(LSocket),
    case catch server_recv(Socket, []) of
        {ok, Packet} -> Pid ! {server, Packet};
        _            -> true
    end,
    catch gen_tcp:close(Socket),
    server_loop(Pid, LSocket).

%%
%%
%%
server_recv(Socket, Bs) ->
    case gen_tcp:recv(Socket, 0, 1000) of
        {ok, B}         -> server_recv(Socket, [Bs, B]);
        {error, closed} -> {ok, binary_to_term(list_to_binary(Bs))}
    end.
