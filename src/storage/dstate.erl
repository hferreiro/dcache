%%%-----------------------------------------------------------------------------
%%% Author  : Henrique Ferreiro <henrique.ferreiro@gmail.com>
%%%-----------------------------------------------------------------------------

-module(storage.dstate).

-behaviour(gen_server).

-import(dict).
-import(gen_server).
-import(io_lib).
-import(lists).

-import(storage.chord).
-import(storage.util.monitor).
-import(storage.util.server).
-import(storage.util.util).

%% --------------------------------------------------------------------
%% Include files
%% --------------------------------------------------------------------
-include("config.hrl").
-include("monitor.hrl").

%% --------------------------------------------------------------------
%% API exports
%% --------------------------------------------------------------------
-export([
	start_link/0,
    get/1,
    put/2,
    del/1,
    del/2,
	set_merge/1,
    set_del/1,
    state/0
		]).

%% --------------------------------------------------------------------
%% External exports
%% --------------------------------------------------------------------
-export([
	rpc_fetch/1,
    rpc_store/1,
    rpc_remove/2,
	rpc_transfer/3
		]).

%% --------------------------------------------------------------------
%% Internal exports
%% --------------------------------------------------------------------
-export([
	handle_request/2,
	fetch/2,
    store/2,
   	remove/3
		]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% --------------------------------------------------------------------
%% Record definitions
%% --------------------------------------------------------------------
-record(state, { dict,  % data dictionary
                 merge, % merge function
                 del	% delete function
				}).

%% --------------------------------------------------------------------
%% Macro definitions
%% --------------------------------------------------------------------
-define(SERVER, ?MODULE).
-define(NODE, rpc:node()).

-define(DICT(State), State#state.dict).
-define(MERGE(State), State#state.merge).
-define(DEL(State), State#state.del).

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
%% @doc Recover the value associated to Key.
%% @spec get(Key) -> {ok, Value} | {error, not_found}
%% @end
%% --------------------------------------------------------------------
get(Key) ->
    server:reentrant_call(?SERVER, {get, Key}).

%% --------------------------------------------------------------------
%% @doc Stores Value with key Key.
%% @spec put(Key, Value) -> ok
%% @end
%% --------------------------------------------------------------------
put(Key, Value) ->
    server:call(?SERVER, {put, Key, Value}).

%% --------------------------------------------------------------------
%% @doc Deletes the Value associated to Key.
%% @spec del(Key) -> ok
%% @end
%% --------------------------------------------------------------------
del(Key) ->
    del(Key, none).

%% --------------------------------------------------------------------
%% @doc Deletes the Value associated to Key using some extra info Info
%% @spec del(Key, Info) -> ok
%% @end
%% --------------------------------------------------------------------
del(Key, Info) ->
    server:call(?SERVER, {del, Key, Info}).

%% --------------------------------------------------------------------
%% @doc Set the merge function
%% @spec set_merge(Merge) -> ok
%% @end
%% --------------------------------------------------------------------
set_merge(Merge) ->
    server:cast(?SERVER, {set_merge, Merge}).

%% --------------------------------------------------------------------
%% @doc Set the del function
%% @spec set_merge(Del) -> ok
%% @end
%% --------------------------------------------------------------------
set_del(Del) ->
    server:cast(?SERVER, {set_del, Del}).

state() ->
    server:call(?SERVER, {state}).

rpc_fetch(Key) ->
    server:reentrant_call(?SERVER, {fetch, Key}).

rpc_store(Values) ->
    server:cast(?SERVER, {store, Values}).

rpc_remove(Key, Info) ->
    server:cast(?SERVER, {remove, Key, Info}).

rpc_transfer(Node, FromId, ToId) ->
    server:cast(?SERVER, {transfer, Node, FromId, ToId}).

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
    monitor:notify(dstate, info, "Initializing dstate"),
    monitor:observer_register(self(), node(), {type, chord}, [transfer]),
    State0 = #state{ dict  = dict:new(),
                     merge = fun(_, _, Value) -> Value end,
					 del   = fun(_, _, _) -> delete end
					},
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
handle_call(Request, From, State) ->
    server:handle_call(?MODULE, Request, From, State).

%% --------------------------------------------------------------------
%% Function: handle_cast/2
%% Description: Handling cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_request({state}, State) ->
    {dict:to_list(?DICT(State)), State};

handle_request({get, Key}, State) ->
	case chord:find_successor(chord:chash(Key)) of
		{ok, Node} ->
			case catch rpc:ecall(State, Node, ?MODULE, fetch, [Key]) of
				{'EXIT', {badrpc, Reason}} ->
					{{error, Reason}, State};
				{Result, NewState} ->
					{Result, NewState}
			end;
		{error, Reason} ->
			{{error, Reason}, State}
	end;

handle_request({put, Key, Value}, State) ->
    case chord:find_successor(chord:chash(Key)) of
        {ok, Node} ->
            case catch rpc:ecall(State, Node, ?MODULE, store, [[{Key, Value}]]) of
				{'EXIT', Reason} ->
                    {{error, Reason}, State};
                {Result, NewState} ->
                    {Result, NewState}
            end;
        {error, Reason} ->
            {{error, Reason}, State}
    end;

handle_request({del, Key, Info}, State) ->
    case chord:find_successor(chord:chash(Key)) of
        {ok, Node} ->
            case catch rpc:ecall(State, Node, ?MODULE, remove, [Key, Info]) of
				{'EXIT', Reason} ->
                    {{error, Reason}, State};
                {Result, NewState} ->
                    {Result, NewState}
            end;
        {error, Reason} ->
            {{error, Reason}, State}
    end;

handle_request({fetch, Key}, State) ->
    {Result, NewState} = fetch(State, Key),
    {Result, NewState};

handle_request({store, Values}, State) ->
    {Result, NewState} = store(State, Values),
    {Result, NewState};

handle_request({remove, Key, Info}, State) ->
    {Result, NewState} = remove(State, Key, Info),
    {Result, NewState};

handle_request({transfer, Node, FromID, ToID}, State) ->
    {Result, NewState} = transfer(State, Node, FromID, ToID),
    {Result, NewState};

handle_request({set_merge, Merge}, State) ->
    {ok, State#state{ merge = Merge }};

handle_request({set_del, Del}, State) ->
    {ok, State#state{ del = Del }};

handle_request(_Request, State) ->
    {{error, unknown_request}, State}.

%% --------------------------------------------------------------------
%% Function: handle_info/2
%% Description: Handling all non call/cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_info({notify, #event{ process_type = chord,
                             event_type   = transfer,
                             data         = {Source, Target, FromID, ToID} } }, State) ->    
    case Source of
        Target ->
            true;
        _ -> 
            case catch rpc:ecall(Source, ?MODULE, transfer, [Target, FromID, ToID]) of
                {'EXIT', nodedown} ->
                    true;
                {'EXIT', Reason} ->
                    % FIXME: true de todas a todas? Non pode ocorrer
                    exit(Reason);
                _Result ->
                    true
            end
    end,
    {noreply, State};

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

%% ====================================================================
%% DState functions
%% ====================================================================

fetch(State, Key) ->
    monitor:notify(dstate, vdebug, io_lib:format("[~p] Fetching key ~p", [?NODE, Key])),
    Result = do_fetch(?DICT(State), Key),
    {Result, State}.

store(State, Values) ->
    monitor:notify(dstate, vdebug, io_lib:format("[~p] Storing pairs ~p", [?NODE, Values])),
    NewDict = do_store(?DICT(State), Values, ?MERGE(State)),
    {ok, State#state{ dict = NewDict}}.

remove(State, Key, Info) ->
    monitor:notify(dstate, vdebug, io_lib:format("[~p] Removing key ~p(~p)", [?NODE, Key, Info])),
    NewDict = do_remove(?DICT(State), Key, Info, ?DEL(State)),
    {ok, State#state{ dict = NewDict }}.

transfer(State, Node, FromID, ToID) ->
    monitor:notify(dstate, vdebug, io_lib:format("[~p] Transferring keys in (~w, ~w] to ~p", [?NODE, FromID, ToID, Node])),
    case do_extract(?DICT(State), FromID, ToID) of
        {[], _} ->
            {ok, State};
		{Values, NewDict} ->
    		rpc:ecall(State#state{ dict = NewDict }, Node, ?MODULE, store, [Values])
	end.

%% ====================================================================
%% Internal functions
%% ====================================================================

do_fetch(Dict, Key) ->
    case dict:find(Key, Dict) of
		{ok, Value} ->
			{ok, Value};
		error ->
			{error, not_found}
	end.

do_store(Dict, [], _Merge) ->
    Dict;

do_store(Dict, [{Key, Value}|Values], Merge) ->
    NewValue = case dict:find(Key, Dict) of
                   {ok, OldValue} ->
                       Merge(Key, OldValue, Value);
			       error ->
                       Value
			   end,
    NewDict = dict:store(Key, NewValue, Dict),
	do_store(NewDict, Values, Merge).

do_remove(Dict, Key, Info, Del) ->
    case dict:find(Key, Dict) of
		{ok, Value} ->
			case Del(Key, Value, Info) of
				delete ->
					dict:erase(Key, Dict);
				NewValue ->
					dict:store(Key, NewValue, Dict)
			end;
		error ->
			Dict
	end.

do_extract(Dict, FromID, ToID) ->
    Max = chord:max(),
    IDs = lists:filter(fun(Id) -> 
                           util:in_seq(chord:chash(Id), util:add(FromID, 1, Max), ToID, Max)
                       end, dict:fetch_keys(Dict)),
    {Values, NewDict} = lists:foldl(fun(Id, {AccIn, DictIn}) ->
                                        {ok, Value} = dict:find(Id, DictIn),
                                        {[{Id, Value}|AccIn], dict:erase(Id, DictIn)}
                                    end, {[], Dict}, IDs),
    {Values, NewDict}.
