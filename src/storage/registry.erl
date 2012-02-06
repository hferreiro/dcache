%%% -------------------------------------------------------------------
%%% Author  : henrique
%%% Description :
%%%
%%% Created : Ago 10,07
%%% -------------------------------------------------------------------
-module(storage.registry).

-behaviour(gen_server).

-import(application).
-import(gen_server).
-import(inet).
-import(lists).
-import(random).

-import(storage.util.config).
-import(storage.util.rpc).
-import(storage.util.util).

%% --------------------------------------------------------------------
%% Include files
%% --------------------------------------------------------------------
-include("config.hrl").

%% --------------------------------------------------------------------
%% External exports
%% --------------------------------------------------------------------
-export([
	start_link/0,
    register/1,
    unregister/1,
    neighbor/1,
    nodes/0,
    snapshot/0,
    new/0,
    name/1
		]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, { registry,
                 nodes
                }).

-define(SERVER, ?MODULE).
-define(NODES(State), State#state.nodes).

%% ====================================================================
%% External functions
%% ====================================================================
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

register(Node) ->
    gen_server:cast({?SERVER, registry_server()}, {register, Node}).

unregister(Node) ->
    gen_server:call({?SERVER, registry_server()}, {unregister, Node}).

neighbor(Node) ->
    gen_server:call({?SERVER, registry_server()}, {neighbor, Node}).

nodes() ->
    gen_server:call({?SERVER, registry_server()}, nodes).

new() ->
    gen_server:call({?SERVER, registry_server()}, new).

name(Name) ->
    gen_server:call({?SERVER, registry_server()}, {name, Name}).

snapshot() ->
    {ok, Nodes} = ?MODULE:nodes(),
    Data = lists:foldl(fun(Node, Acc) ->
                           [{Node, rpc:call(Node, storage.chord, get_successor, []), rpc:call(Node, storage.chord, get_fingers, [])}|Acc]
                       end, [], Nodes),
    {ok, Data}.

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
init([]) ->
    config:start_link(),
    application:start(crypto),
    State0 = #state{ nodes = [] },
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
handle_call({neighbor, Node}, _From, State) ->
    case lists:delete(Node, ?NODES(State)) of
        [] ->
            {reply, {error, not_found}, State};
		Nodes ->
            {reply, {ok, util:random_nth(Nodes)}, State}
	end;

handle_call({unregister, Node}, _From, State) ->
	{reply, ok, State#state{ nodes = lists:delete(Node, ?NODES(State)) }};

handle_call(nodes, _From, State) ->
    NewNodes = lists:foldl(fun(Node, Acc) ->
                               case rpc:call(Node, storage.chord, ping, []) of   
                                   pong ->
                                       [Node|Acc];
                                   _ ->
                                       Acc
                               end
                           end, [], ?NODES(State)),   
    {reply, {ok, NewNodes}, State#state{ nodes = NewNodes }};

handle_call(new, _From, State) ->
    {reply, {ok, new(?NODES(State))}, State};

handle_call({name, Name}, _From, State) ->
    {reply, {ok, name(?NODES(State), Name)}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% --------------------------------------------------------------------
%% Function: handle_cast/2
%% Description: Handling cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_cast({register, Node}, State) ->
	NewNodes = [Node | lists:delete(Node, ?NODES(State))],
    {noreply, State#state{ nodes = NewNodes }};

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
terminate(_Reason, _State) ->
    ok.

%% --------------------------------------------------------------------
%% Func: code_change/3
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState}
%% --------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%%

new(Nodes) ->
    N = 100,
    Name = integer_to_list(random:uniform(N)),
    Node = list_to_atom(Name ++ "@" ++ hostname()),
    case lists:member(chord:chash(Node), hashed(Nodes)) of
        true ->
            new(Nodes);
        false ->
            Name
    end.

name([], _Name) ->
    "";
name([Node|Nodes], Name) ->
    case integer_to_list(chord:chash(Node)) of
        Name ->
            Node2 = atom_to_list(Node),
            lists:sublist(Node2, 1, length(Node2) - length(hostname()) - 1);
        _ ->
            name(Nodes, Name)
    end.

hashed([]) ->
    [];
hashed([Node|Nodes]) ->
    [chord:chash(Node)|hashed(Nodes)].

registry_server() ->
    util:a2a(?REGISTRY ++ "@" ++ hostname()).

hostname() ->
    {ok, Hostname} = inet:gethostname(),
    Hostname.
