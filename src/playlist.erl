-module(playlist).
-behaviour(gen_server).

-import(application).
-import(gen_server).
-import(lists).
-import(timer).

-import(playlist.scheduler).
-import(storage.util.config).
-import(storage.util.monitor).
-import(storage.util.util).
-import(storage.storage).

%% --------------------------------------------------------------------
%% Include files
%% --------------------------------------------------------------------
-include("config.hrl").
-include("playlist.hrl").

%% --------------------------------------------------------------------
%% API exports
%% --------------------------------------------------------------------
-export([
    start/0,
    stop/1,

    add/4,
    remove/3,
    remove_list/1,
    update/4
		]).

%% --------------------------------------------------------------------
%% Internal exports
%% --------------------------------------------------------------------
-export([
    schedule/0,
    download/2,
    cancel/1,
    getlist/0,

    state/0   
        ]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% --------------------------------------------------------------------
%% Record definitions
%% --------------------------------------------------------------------
-record(state, { scheduled,
                 playlist,
                 free
                }).

%% --------------------------------------------------------------------
%% Macro definitions
%% --------------------------------------------------------------------
-define(NODE, node()).

-define(SCHEDULED(State), State#state.scheduled).
-define(PLAYLIST(State), State#state.playlist).
-define(FREE(State), State#state.free).

%% ====================================================================
%% External functions
%% ====================================================================

%% --------------------------------------------------------------------
%% @doc Starts the server.
%% @spec start_link() -> {ok, Pid} | {error, Reason}
%% @end
%% --------------------------------------------------------------------
start() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

stop([Node]) ->
    gen_server:call({?MODULE, Node}, stop),
    rpc:call(Node, init, stop, []).

add(ListId, MO, Server, Tst) ->
    gen_server:call(?MODULE, {add, ListId, MO, Server, Tst}).

remove(ListId, MO, Tst) ->
    gen_server:call(?MODULE, {remove, ListId, MO, Tst}).

remove_list(ListId) ->
    gen_server:call(?MODULE, {remove_list, ListId}).

update(ListId, MO, Tst, NewTst) ->
    gen_server:call(?MODULE, {update, ListId, MO, Tst, NewTst}).

getlist() ->
    gen_server:call(?MODULE, getlist).

state() ->
    gen_server:call(?MODULE, state).
schedule() ->
    gen_server:cast(?MODULE, schedule).

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
init(_) ->
    case application:start(storage) of
        ok ->
            monitor:notify(playlist, info, io_lib:format("[~p] Initializing playlist", [?NODE])),
            State0 = #state{ scheduled = [],
                             playlist  = [],
                             free      = config:get_parameter(?STORAGE_SIZE)
                            },
            timer:apply_interval(config:get_parameter(?PLAYLIST_SCHEDULER_INTERVAL), ?MODULE, schedule, []),
            {ok, State0};
        {error, Reason} ->
            {stop, Reason}
    end.

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
handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

handle_call({add, ListId, MO, Server, Tst}, _From, State) ->
    {ok, Result, NewState} = add(State, ListId, MO, Server, Tst),
    {reply, Result, NewState};

handle_call({remove, ListId, MO, Tst}, _From, State) ->
    {ok, Result, NewState} = remove(State, ListId, MO, Tst),
    {reply, Result, NewState};

handle_call({remove_list, ListId}, _From, State) ->
    {ok, Result, NewState} = remove_list(State, ListId),
    {reply, Result, NewState};

handle_call({update, ListId, MO, Tst, NewTst}, _From, State) ->
    {ok, Result, NewState} = update(State, ListId, MO, Tst, NewTst),
    {reply, Result, NewState};

handle_call(getlist, _From, State) ->
    {ok, Result, NewState} = getlist(State),
    {reply, Result, NewState};

handle_call(state, _From, State) ->
    {reply, {?SCHEDULED(State), ?PLAYLIST(State), ?FREE(State)}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% --------------------------------------------------------------------
%% Function: handle_cast/2
%% Description: Handling cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_cast(schedule, State) ->
    {ok, NewState} = schedule(State),
    {noreply, NewState};

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
    application:stop(storage),
    ok.

%% Func: code_change/3
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState}
%% --------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ====================================================================
%% Internal functions
%% ====================================================================

add(State, ListId, MO, Server, Tst) ->
    monitor:notify(playlist, info, io_lib:format("[~p] Adding ~p - ~p to playlist", [?NODE, ListId, MO])),
    case util:file_size({Server, MO}) of
        {ok, Size} ->
            monitor:notify(playlist, debug, io_lib:format("[~p] Size is ~p", [?NODE, Size])),
            Item = mkitem(ListId, MO, Server, Size, Tst),
            PlayList = insert_by_tst(?PLAYLIST(State), Item),
            monitor:notify(playlist, debug, io_lib:format("[~p] New playlist is ~p", [?NODE, PlayList])),
            {ok, ok, State#state{ playlist = PlayList }};
        {error, Reason} ->
            monitor:notify(playlist, debug, io_lib:format("[~p] Error while retrieving size - ~p", [?NODE, Reason])),
            {ok, {error, Reason}, State}
    end.

remove(State, ListId, MO, Tst) ->
    monitor:notify(playlist, info, io_lib:format("[~p] Removing ~p - ~p from playlist", [?NODE, ListId, MO])),
    {Item, PlayList} = remove(?PLAYLIST(State), {ListId, MO, Tst}),
    {ok, ok, State#state{ scheduled = [Item|?SCHEDULED(State)], playlist = PlayList }}.

remove_list(State, ListId) ->
    {Removed1, PlayList} = remove_by_list(?PLAYLIST(State), ListId),
    {Removed2, Scheduled} = remove_by_list(?SCHEDULED(State), ListId),
    delete(Removed1 ++ Removed2),
    {ok, ok, State#state{ scheduled = Scheduled, playlist = PlayList }}.

update(State, ListId, MO, Tst, NewTst) ->
    monitor:notify(playlist, info, io_lib:format("[~p] Updating ~p - ~p", [?NODE, ListId, MO])),
    {Item, PlayList} = remove(?PLAYLIST(State), {ListId, MO, Tst}),
    NewPlayList = insert_by_tst(PlayList, Item#item{ tst = NewTst }),
    {ok, ok, State#state{ playlist = NewPlayList }}.

getlist(State) ->
    Scheduled = sort_by_tst(?SCHEDULED(State)),
    List = lists:reverse(list_to_list(Scheduled)) ++ list_to_list(?PLAYLIST(State)),
    {ok, add_state(List), State}.

add_state([]) ->
    [];
add_state([{ListId, MO, TST}|Rest]) ->
    State = case storage.storage:resource_state(MO) of
                {error, _} ->
                    "none";
                {St, _} ->
                    util:a2l(St)
            end,
    [{ListId, MO, TST, State}|add_state(Rest)].
    %{State, Progress} = case storage.storage:resource_state(MO) of
    %                        {error, _} ->
    %                            {none, 0};
    %                        {St, Prog} ->
    %                            case St of
    %                                pending ->
    %                                    {St, 0};
    %                                ready ->
    %                                    {St, 100};
    %                                _ ->
    %                                    {P, _} = Prog,
    %                                    {St, P}
    %                            end
    %                    end,
    %[{ListId, MO, TST, util:a2l(State), util:a2l(Progress)}|add_state(Rest)].

item_to_list(Item) ->
    {H, M, _S} = ?TST(Item),
    {?LISTID(Item), ?MO(Item), {H, M}}.

list_to_list(List) ->
    lists:map(fun item_to_list/1, List).

schedule(State) ->
    monitor:notify(playlist, vdebug, io_lib:format("[~p] Scheduling", [?NODE])),
    {{Scheduled, PlayList}, Free} = scheduler:schedule({?SCHEDULED(State), ?PLAYLIST(State)}, ?FREE(State),
                                                       fun download/2, fun cancel/1),
    {ok, State#state{ scheduled = Scheduled, playlist = PlayList, free = Free }}.

download(MO, Server) ->
    monitor:notify(playlist, vdebug, io_lib:format("[~p] Downloading ~p from ~p~n", [?NODE, MO, Server])),
    storage:add_resource(MO, Server).

cancel(MO) ->
    storage:cancel_resource(MO).

% helpers

mkitem(ListId, MO, Server, Size, Tst) ->
    #item{ listid = ListId, mo = MO, server = Server, size = Size, tst = Tst }.

insert_by_tst(PlayList, Item) ->
    lists:merge(fun(Item1, Item2) ->
                     ?TST(Item1) =< ?TST(Item2)
                 end, PlayList, [Item]).

remove(PlayList, {ListId, MO, Tst}) ->
    Filter = fun(#item{ listid = TheListId, mo = TheMO, tst = TheTst }) ->
        		 {TheListId, TheMO, TheTst} == {ListId, MO, Tst}
			 end,
	[Item] = lists:filter(Filter, PlayList),
	{Item, lists:delete(Item, PlayList)}.

remove_by_list(PlayList, ListId) ->
    FilterIn = fun(#item{ listid = TheListId }) ->
        	       TheListId /= ListId
			   end,
    FilterOut = fun(#item{ listid = TheListId }) ->
        	        TheListId == ListId
			    end,
	{lists:filter(FilterOut, PlayList), lists:filter(FilterIn, PlayList)}.

insert_by_tst_(List, Item) ->
    lists:merge(fun(Item1, Item2) ->
                    ?TST(Item1) >= ?TST(Item2)
                end, List, [Item]).

sort_by_tst(List) ->
    lists:foldl(fun(Item, Acc) ->
                    insert_by_tst_(Acc, Item)
                end, [], List).

delete([]) ->
    ok;
delete([Item|Rest]) ->
    storage:cancel_resource(?MO(Item)),
    delete(Rest).
