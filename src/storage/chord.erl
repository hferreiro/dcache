%%% -------------------------------------------------------------------
%%% Author  : Henrique Ferreiro García <henrique.ferreiro@gmail.com>
%%% Description :
%%%
%%% Created : Xul 11,07
%%% -------------------------------------------------------------------

-module(storage.chord).
-behaviour(gen_server).

-import(crypto).
-import(gen_server).
-import(io_lib).
-import(lists).
-import(math).
-import(timer).
-import(io).

-import(storage.util.config).
-import(storage.util.monitor).

%% --------------------------------------------------------------------
%% Include files
%% --------------------------------------------------------------------
-include("config.hrl").

%% --------------------------------------------------------------------
%% API exports
%% --------------------------------------------------------------------
-export([
	start_link/0,
    find_successor/1,
    chash/1,
    max/0,
    state/0
		]).

%% --------------------------------------------------------------------
%% External exports
%% --------------------------------------------------------------------
-export([
    get_predecessor/0,
    get_successor_list/0,
    notify/1,
    ping/0,

    get_successor/0,
    get_fingers/0
		]).

%% --------------------------------------------------------------------
%% Internal exports
%% --------------------------------------------------------------------
-export([
    fix_fingers/0,
    stabilize/0
		]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% --------------------------------------------------------------------
%% Record definitions
%% --------------------------------------------------------------------
-record(state, { successor_list,
                 fingers,
                 predecessor
                }).

%% --------------------------------------------------------------------
%% Macro definitions
%% --------------------------------------------------------------------
-define(SERVER, ?MODULE).

-define(NODE, rpc:node()).
-define(M, config:get_parameter(?CHORD_M)).
-define(N, chash(?NODE)).
-define(SUCCESSOR, ?FINGER(1)).
-define(SUCCESSOR_LIST, gen_server:call(?SERVER, {get_successor_list})).
-define(PREDECESSOR, gen_server:call(?SERVER, {get_predecessor})).
-define(FINGER(I), gen_server:call(?SERVER, {get_finger, I})).
-define(FINGER_START(I), get_finger_start(I)).
-define(FINGERS, gen_server:call(?SERVER, {get_fingers})).
-define(SET_FINGER(I, Node), gen_server:cast(?SERVER, {set_finger, I, Node})).
-define(SET_SUCCESSOR(Node), ?SET_FINGER(1, Node)).
-define(SET_SUCCESSOR_LIST(List), gen_server:cast(?SERVER, {set_successor_list, List})).
-define(SET_PREDECESSOR(Node), gen_server:cast(?SERVER, {set_predecessor, Node})).

%% ====================================================================
%% External functions
%% ====================================================================

%% --------------------------------------------------------------------
%% @doc Starts the server.
%% @spec start_link() -> {ok, Pid} | {error, Reason}
%% @end
%% --------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% --------------------------------------------------------------------
%% @doc Finds the successor of a node.
%% <pre>
%% Types:
%%  Id = atom()
%% </pre>
%% @spec find_successor(Id) -> {ok, Node}
%% @end
%% --------------------------------------------------------------------
find_successor(Id) ->
    monitor:notify(chord, vvdebug, io_lib:format("[~p] find_successor(~p)", [?NODE, Id])),
    case in_oc_interval(Id, ?N, chash(?SUCCESSOR)) of
    	true ->
            {ok, ?SUCCESSOR};
        false ->
            List = closest_preceding_nodes(Id),
            monitor:notify(chord, vvdebug, io_lib:format("closest_preceding_nodes ~p", [List])),
            check_preceding_nodes(List, Id)
	end.

check_preceding_nodes([], _Id) ->
    ok = join(),
    monitor:notify(chord, vdebug, io_lib:format("[~p] no finger alive", [?NODE])),
    {error, no_finger_alive};
check_preceding_nodes([Node|Rest], Id) ->
	case catch rpc(Node, find_successor, [Id]) of
		{'EXIT', {badrpc, nodedown}} ->
			check_preceding_nodes(Rest, Id);
		{'EXIT', Reason} ->
			exit(Reason);
		Result ->
			Result
	end.

chash(Value) ->
    Str = binary_to_list(term_to_binary(Value)),
    Hash = binary_to_list(crypto:sha(Str)),
    chash(Hash, length(Hash)-1, 0) rem round(math:pow(2, ?M)).

chash([], _, Acc) ->
    Acc;
chash([Value | Rest], Pos, Acc) ->
    chash(Rest, Pos - 1, Acc + Value * round(math:pow(256, Pos))).

max() ->
    round(math:pow(2, ?M)).

get_predecessor() ->
    % FIXME: neste momento podo borrar as claves que transferín ao meu predecesor, non se hai lista de sucesores
    gen_server:call(?SERVER, {get_predecessor}).

get_successor_list() ->
    gen_server:call(?SERVER, {get_successor_list}).

notify(Node) ->
    monitor:notify(chord, vvdebug, io_lib:format("[~p] notified by ~p", [?NODE, Node])),
    case ?PREDECESSOR of
        nil ->
            ok = ?SET_PREDECESSOR(Node);
        Predecessor ->
            case in_oo_interval(chash(Node), chash(Predecessor), ?N) of
                true ->
                    ok = ?SET_PREDECESSOR(Node);
                false ->
                    % check_predecessor()
                    case catch rpc(Predecessor, ping, []) of
                        pong ->
                            ok;
                        {'EXIT', {badrpc, nodedown}} ->
                            ok = ?SET_PREDECESSOR(Node);
						{'EXIT', Reason} ->
                            exit(Reason)
					end
			end
	end,
	ok.

ping() ->
    pong.

get_successor() ->
    ?SUCCESSOR.

get_fingers() ->
    ?FINGERS.


state() ->
    gen_server:call(?SERVER, {state}).

%% ====================================================================
%% Server functions
%% ====================================================================

%% --------------------------------------------------------------------
%% Function: init/1
%% Description: Initiates the server
%% Returns: {ok, State}          |
%%          {ok, State, Timeout} |
%%          ignore               |
%%          {stop, Reason}
%% --------------------------------------------------------------------
init(_Args) ->
    process_flag(trap_exit, true),
    monitor:notify(chord, info, io_lib:format("Initializing chord node ~p", [?NODE])),
    ok = join(),
	{ok, _} = timer:apply_interval(config:get_parameter(?CHORD_SUCCESSORS_STABILIZATION, 1000), ?MODULE, stabilize, []),
	{ok, _} = timer:apply_interval(config:get_parameter(?CHORD_FINGERS_STABILIZATION, 5000), ?MODULE, fix_fingers, []),
	State0 = #state{successor_list = [nil || _ <- lists:seq(1, config:get_parameter(?CHORD_SUCCESSOR_LIST_SIZE))],
					fingers        = [nil || _ <- lists:seq(1, ?M)],
                    predecessor    = nil},
	ok = registry:register(?NODE),
	{ok, State0}.

%% --------------------------------------------------------------------
%% Function: handle_call/3
%% Description: Handling call messages
%% Returns: {reply, Reply, State}          |
%%          {reply, Reply, State, Timeout} |
%%          {noreply, State}               |
%%          {noreply, State, Timeout}      |
%%          {stop, Reason, Reply, State}   | (terminate/2 is called)
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_call({get_predecessor}, _From, State) ->
    {reply, State#state.predecessor, State};

handle_call({get_successor_list}, _From, State) ->
    {reply, State#state.successor_list, State};

handle_call({get_finger, I}, _From, State) ->
    FingerI = get_finger(I, State#state.fingers),
    {reply, FingerI, State};

handle_call({get_fingers}, _From, State) ->
    {reply, State#state.fingers, State};

handle_call({state}, _From, State) ->
    {reply, State, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% --------------------------------------------------------------------
%% Function: handle_cast/2
%% Description: Handling cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_cast({set_finger, 1, Node}, State) ->
    NewSuccessor = case get_finger(1, State#state.fingers) of
                       nil ->
                           true;
                       Finger1 ->
                           Finger1 /= Node
                   end,
    case NewSuccessor of
        true ->
            case State#state.predecessor of
                % TODO: Transfer debería copiar e non mover os datos
                nil ->
                    % FIXME: para que de tempo a que arranque dstate
                    timer:sleep(100),
        			monitor:notify(chord, transfer, {Node, ?NODE, chash(Node), ?N});
                Predecessor ->
                    monitor:notify(chord, transfer, {Node, ?NODE, chash(Predecessor), ?N})
            end;
        _ ->
            true
    end,
    {noreply, State#state{ fingers = set_finger(1, State#state.fingers, Node) }};

handle_cast({set_finger, I, Node}, State) ->
    {noreply, State#state{ fingers = set_finger(I, State#state.fingers, Node) }};

handle_cast({set_successor_list, List}, State) ->
	{noreply, State#state{ successor_list = List }};

handle_cast({set_predecessor, Node}, State) ->
    {noreply, State#state{ predecessor = Node}};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% --------------------------------------------------------------------
%% Function: handle_info/2
%% Description: Handling all non call/cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%% --------------------------------------------------------------------
%% Function: terminate/2
%% Description: Shutdown the server
%% Returns: any (ignored by gen_server)
%% --------------------------------------------------------------------
terminate(_Reason, State) ->
    case get_finger(1, State#state.fingers) of
        nil ->
            true;
        Successor ->
            monitor:notify(chord, transfer, {?NODE, Successor, chash(Successor), ?N}),
            timer:sleep(3000)
    end,
    registry:unregister(?NODE),
    ok.

%% --------------------------------------------------------------------
%% Func: code_change/3
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState}
%% --------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ====================================================================
%% Internal functions
%% ====================================================================

fix_fingers() ->
    lists:foreach(fun(I) ->
       				  {ok, S} = find_successor(?FINGER_START(I)),
                      ok = ?SET_FINGER(I, S)
				  end, lists:seq(2, ?M)),
    ok.

stabilize() ->
	case catch rpc(?SUCCESSOR, get_predecessor, []) of
        {'EXIT', {badrpc, nodedown}} ->
            case catch new_successor(?SUCCESSOR_LIST) of
                {'EXIT', {badrpc, nodedown}} ->
				    monitor:notify(chord, vdebug, io_lib:format("[~p] stabilize failed: no successor in list", [?NODE])),
                    ok = join();
                {'EXIT', Reason} ->
                    monitor:notify(chord, vdebug, io_lib:format("[~p] stabilize failed with ~p", [?NODE, Reason])),
                    ok = join();
				Node ->
				    monitor:notify(chord, vdebug, io_lib:format("[~p] stabilize: successor failed, new is ~p", [?NODE, Node])),
                    ok = ?SET_SUCCESSOR(Node),
                    ok = rpc(?SUCCESSOR, notify, [?NODE])
			end;
		{'EXIT', Reason} ->
            exit(Reason);
        nil ->
            true;
		Successor ->
            case in_oo_interval(chash(Successor), ?N, chash(?SUCCESSOR)) of
        		true ->
        		    monitor:notify(chord, vdebug, io_lib:format("[~p] stabilize: setting new successor ~p", [?NODE, Successor])),
            		ok = ?SET_SUCCESSOR(Successor),
					ok = reconcile(Successor),
                    ok = rpc(?SUCCESSOR, notify, [?NODE]);
        		false ->
            		true
			end
	end,
	ok.

closest_preceding_nodes(Id) ->
    monitor:notify(chord, vvdebug, io_lib:format("[~p] closest_preceding_nodes(~p)", [?NODE, Id])),
    N = ?N,
    List = lists:filter(fun(Elem) ->
							in_oo_interval(chash(Elem), N, Id)
						end, ?SUCCESSOR_LIST ++ ?FINGERS),
    lists:usort(fun(NodeA, NodeB) ->
				    chash(NodeA) >= chash(NodeB)
			    end, List).

join() ->
    case registry:neighbor(?NODE) of
        {ok, Node} ->
            case catch join(Node) of
				{'EXIT', Reason} ->
                    monitor:notify(chord, vdebug, io_lib:format("[~p] Join failed with ~p", [?NODE, Reason])),
                    ok = registry:unregister(Node),
                    ok = join();
				ok ->
                    ok
			end;
		{error, not_found} ->
            ok = create()
	end.

create() ->
    monitor:notify(chord, info, io_lib:format("[~p] Creating chord ring", [?NODE])),
    ok = ?SET_PREDECESSOR(?NODE),
	lists:foreach(fun(I) ->
        				ok = ?SET_FINGER(I, ?NODE)
                  end, lists:seq(1, ?M)),
    ?SET_SUCCESSOR_LIST(lists:duplicate(config:get_parameter(?CHORD_SUCCESSOR_LIST_SIZE), ?NODE)),
    ok.

join(Node) ->
    monitor:notify(chord, info, io_lib:format("[~p] Joining chord ring with ~p", [?NODE, Node])),
    ok = ?SET_PREDECESSOR(nil),
    {ok, Successor} = rpc(Node, find_successor, [?N]),
    lists:foreach(fun(I) ->
        				ok = ?SET_FINGER(I, Successor)
                  end, lists:seq(1, ?M)),
    ok = reconcile(Successor),
    rpc(Successor, notify, [?NODE]),
    ok.

new_successor([]) ->
    exit({badrpc, nodedown});
new_successor([Node|Rest]) ->
    case catch reconcile(Node) of
        {'EXIT', {badrpc, nodedown}} ->
			new_successor(Rest);
		{'EXIT', Reason} ->
            exit(Reason);
		ok ->
            Node
	end.

reconcile(Node) ->
    List = rpc(Node, get_successor_list, []),
    ok = ?SET_SUCCESSOR_LIST([Node|lists:sublist(List, length(List) - 1)]).

%% Finger operations

get_finger_start(I) ->
	(?N + round(math:pow(2, I-1))) rem max().

get_finger(N, L) ->
    lists:nth(N, L).

set_finger(N, L, E) ->
    do_set_finger(N, L, E, []).

do_set_finger(1, [_|T], E, Acc) ->
    lists:reverse(Acc) ++ [E|T];
do_set_finger(N, [H|T], E, Acc) ->
    do_set_finger(N-1, T, E, [H|Acc]).

%% Utils

rpc(Node, Func, Args) ->
    case ?NODE of
        Node ->
            apply(?MODULE, Func, Args);
        _ ->
            case rpc:call(Node, ?MODULE, Func, Args) of
                {badrpc, Reason} ->
                    exit({badrpc, Reason});
				Result ->
                    Result
            end
	end.

in_oc_interval(X, A, B) ->
    ((X > A) and (X =< B)) or ((X > A) and (B < A)) or ((X =< B) and (B < A)) or (A == B).

in_oo_interval(X, A, B) ->
    ((X > A) and (X < B)) or ((X > A) and (B < A)) or ((X < B) and (B < A)) or ((A == B) and (X /= A)).
