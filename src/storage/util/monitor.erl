%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : Local event mediator for the Observer Pattern (from VoDKA project)
%%%-----------------------------------------------------------------------------

-module(storage.util.monitor).
-behaviour(gen_server).

-import(lists).
-import(dict).
-import(ets).
-import(gen_server).
-import(storage.util.util).
-import(storage.util.config).

-include("monitor.hrl").
-include("util.hrl").
-include("config.hrl").

%% Public API
-export([start_link/0]).
-export([notify/3, declare/2, declare/1]).
-export([observer_register/1, observer_register/2, observer_register/3]).
-export([observer_register/4, observer_register/5, observer_register/6]).
-export([observer_popup_register/7, observer_popup_register/8]).
-export([observer_notify/2, observer_unregister/1, observer_unregister/2]).
%% Private API
-export([internal_register/3, internal_register/5, real_notify/3, no_notify/3]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {any}).

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
notify(ProcessType, EventType, Data) ->
    apply(?MODULE, config:get_parameter(?MONITOR_NOTIFY), [ProcessType, EventType, Data]).

%%
%%
%%
no_notify(_, _, _) ->
    ok.

%%
%%
%%
real_notify(ProcessType, EventType, Data) ->
    gen_server:cast(?MODULE, {notify, now(), ProcessType, self(), EventType, Data}).

%%
%%
%%
declare(Pid, ProcessType) ->
    gen_server:cast(?MODULE, {declare, Pid, ProcessType}).

%%
%%
%%
declare(ProcessType) ->
    declare(self(), ProcessType).

%%
%%
%%
observer_register(Pid, Node, Clause, EventTypes, ResponseF, ResponseData) ->
    gen_server:call({?MODULE, Node}, {register, Pid, Clause, EventTypes, ResponseF, ResponseData}).

%%
observer_register(Node, Clause, EventTypes, ResponseF, ResponseData) ->
    observer_register(self(), Node, Clause, EventTypes, ResponseF, ResponseData).

%%
observer_register(Pid, Node, Clause, EventTypes) ->
    observer_register(Pid, Node, Clause, EventTypes, fun observer_notify/2, Pid).

%%
observer_register(Pid, Node, Events) when list(Events), pid(Pid) ->
    observer_register(Pid, Node, ?ANY_PROCESS, Events);
observer_register(Pid, Node, Clause) when pid(Pid) ->
    observer_register(Pid, Node, Clause, ?ANY_EVENT);
observer_register(Node, Clause, EventTypes) ->
    observer_register(self(), Node, Clause, EventTypes, fun observer_notify/2, self()).

%%
observer_register(Node, Events) when list(Events) ->
    observer_register(self(), Node, ?ANY_PROCESS, Events);
observer_register(Pid, Node) when pid(Pid) ->
    observer_register(Pid, Node, ?ANY_PROCESS, ?ANY_EVENT);
observer_register(Node, Clause) ->
    observer_register(self(), Node, Clause, ?ANY_EVENT).

%%
observer_register(Node) ->
    observer_register(self(), Node, ?ANY_PROCESS, ?ANY_EVENT).

%%
%%
%%
observer_popup_register(Node, Clause, Events, ObserverM, EventAdapter, MoreArgsF, PopupEvents) -> 
    observer_popup_register(self(), Node, Clause, Events, ObserverM, EventAdapter, MoreArgsF, PopupEvents).

%%
observer_popup_register(Pid, Node, Clause, Events, {TargetNode,ObserverM}, EventAdapter, MoreArgsF, PopupEvents) -> 
    F = fun (E, ArgF) ->
		P = ObserverM:start_link(TargetNode, EventAdapter, ArgF(E)),
		monitor:internal_register(P, {name, E#event.process_id}, PopupEvents, fun observer_notify/2, P),
		P ! {notify, E}
	end,
    observer_register(Pid, Node, Clause, Events, F, MoreArgsF);
observer_popup_register(Pid, Node, Clause, Events, ObserverM, EventAdapter, MoreArgsF, PopupEvents) -> 
    observer_popup_register(Pid, Node, Clause, Events, {node(), ObserverM}, EventAdapter, MoreArgsF, PopupEvents).

%%
%%
%%
observer_unregister(Pid, Node) ->
    gen_server:call({?MODULE, Node}, {unregister, Pid}).

%%
observer_unregister(Pid) when pid(Pid) ->
    observer_unregister(Pid, node());
observer_unregister(Node) ->
    observer_unregister(self(), Node).

%%
%%
%%
observer_notify(Event, Pid) ->
    Pid ! {notify, Event}.

%%%-----------------------------------------------------------------------------
%%% gen_server interface
%%%-----------------------------------------------------------------------------

%%
%%
%%
init(_) ->
    process_flag(trap_exit, true),
    lists:foreach(fun (T) -> ets:new(T, [set, named_table, protected]) end, ?VALID_CLAUSES),
    ets:new(?OBSERVERS, [bag, named_table, protected]),
    ets:new(?DECLARED, [set, named_table, protected]),
    State0 = #state{ any = dict:new() },
    {ok, State0}.

%%
%%
%%
handle_call({register, Pid, ?ANY_PROCESS, EventTypes, ResponseF, ResponseArg}, _, State) ->
    NewState = State#state{ any = dict:store(Pid, {EventTypes, ResponseF, ResponseArg}, State#state.any) },
    {reply, ok, NewState};

handle_call({register, Pid, Clause, EventTypes, ResponseF, ResponseArg}, _, State) ->
    Reply = internal_register(Pid, Clause, EventTypes, ResponseF, ResponseArg),
    {reply, Reply, State};

handle_call({unregister, Pid}, _, State) ->
    NState = internal_unregister(State, Pid),
    {reply, ok, NState};

handle_call(_, _, State) ->
    {reply, unknown_request, State}.

%%
%%
%%
handle_cast({notify, TimeStamp, ProcessType, ProcessId, EventType, Data}, State) ->
    {noreply, notify(State, TimeStamp, ProcessType, ProcessId, EventType, Data)};

handle_cast({declare, Pid, ProcessType}, State) ->
    {noreply, internal_declare(State, Pid, ProcessType)};

handle_cast(_, State) ->
    {noreply, State}.

%%
%%
%%
handle_info({'EXIT',Pid,Reason}, State) ->
    NState = case ets:lookup(?DECLARED, Pid) of
		 [] -> %% an observer...
		     internal_unregister(State, Pid);
		 [{_,ProcessType}] ->  %% a declared monitored subject
		     NS = notify(State, erlang:now(), ProcessType, Pid, 'EXIT', Reason),
		     ets:delete(?DECLARED, Pid),
		     NS
	     end,
    {noreply, NState};

%% handle_info(Info, State)
handle_info(_, State) ->
    {noreply, State}.

%%
%%
%%
%% terminate(Reason, State)
terminate(_, _) ->
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
internal_unregister(State, Pid) ->
    NState = State#state{ any = dict:erase(Pid, State#state.any) },
    Instances = ets:lookup(?OBSERVERS, Pid),
    lists:foreach(fun ({_,T,V}) ->  
			  case ets:lookup(T,V) of
			      [{_,Dict}] ->
				  NDict = dict:erase(Pid,Dict),
				  case dict:size(NDict) of
				      0 ->
					  ets:delete(T,V);
				      _ ->
					  ets:insert(T,{V,NDict})
				  end
			  end		  
		  end, Instances),    
    ets:delete(?OBSERVERS, Pid),
    NState.

%%
%%
%%
internal_register(From, Clause, EventTypes) ->
    internal_register(From, Clause, EventTypes, fun observer_notify/2, From).

%%
%%
%%
internal_register(From, {Tag, Value}, EventTypes, ResponseF, ResponseArg) ->
   case catch ets:lookup(Tag, Value) of
	[] ->
	    set_observer(Tag, Value, From, {EventTypes, ResponseF, ResponseArg}, dict:new());
	[{Value, Dict}] ->
	    set_observer(Tag, Value, From, {EventTypes, ResponseF, ResponseArg}, Dict);
	_ ->
	    {error, unknown_clause_tag}
    end.

%%
%%
%%
set_observer(Tag, Value, From, Data, Dict) ->
    if
	Tag==?NAME ->   %% name declared process
	    case ets:lookup(?DECLARED, Value) of
		[] ->
		    link(Value),
		    ets:insert(?DECLARED, {Value, undefined});
		_ ->
		    ok
	    end;
	true ->
	    ok	    
    end,
    link(From),
    ets:insert(?OBSERVERS, {From,Tag,Value}),
    ets:insert(Tag, {Value, dict:store(From, Data, Dict)}).

%%
%%
%%
notify(State, TimeStamp, ProcessType, ProcessId, EventType, Data) ->
    Event = #event{ timestamp    = TimeStamp,
          	    process_type = ProcessType,
 	            process_id   = ProcessId,
		    event_type   = EventType,
		    data         = Data },
    EventFilter = event_filter(EventType),
    SpecificObserverList = [ dict:filter(EventFilter, select_observers(T, V)) ||
			     {T,V} <- [{?NAME, ProcessId}, {?TYPE, ProcessType}]],
    Observers = lists:foldl(fun (D1,D2) ->
				    dict:merge(fun merge_response/3, D1, D2)
			    end, dict:filter(EventFilter, State#state.any), SpecificObserverList),
    dict:fold(fun (_, {_, ResponseF, ResponseArg}, _) ->
		      ResponseF(Event, ResponseArg);
		  (_, L, _) ->
		      lists:foreach(fun ({ResponseF, ResponseArg}) ->
					    ResponseF(Event, ResponseArg)
				    end, L)
	      end, ok, Observers),
    State.

%%
select_observers(Tag, Value) ->
    case ets:lookup(Tag, Value) of
	[] ->
	    dict:new();
	[{Value, Dict}] ->
	    Dict
    end.

%%
event_filter(Event) -> 
    fun (_, {?ANY_EVENT,_,_}) ->
	    true;
	(_, {Events,_,_}) ->
	    lists:member(Event, Events)
    end.

%%
merge_response(_, {_,F,A}=V, {_,F,A}) ->
    V;
merge_response(_, {_,F1,A1}, {_,F2,A2}) ->
    [{F1,A1}, {F2,A2}];
merge_response(_, {_,F,A}, L) ->
    case lists:member({F,A}, L) of
	true ->
	    L;
	_ ->
	    [{F,A} | L]
    end.

%%
%%
%%
internal_declare(State, Pid, ProcessType) ->
    link(Pid),
    ets:insert(?DECLARED, {Pid, ProcessType}),
    State.
