-module(storage.storage).
-behaviour(gen_server).

-import(dets).
-import(gen_server).
-import(io_lib).
-import(lists).

-import(storage.util.config).
-import(storage.util.monitor).
-import(storage.util.util).

%% --------------------------------------------------------------------
%% Include files
%% --------------------------------------------------------------------
-include("config.hrl").
-include("storage.hrl").

%% --------------------------------------------------------------------
%% API exports
%% --------------------------------------------------------------------
-export([
	start_link/0,
	add_resource/2,
    add_resource/3,
    cancel_resource/1,
    resource_state/1,
    cache_state/0
		]).

%% --------------------------------------------------------------------
%% External exports
%% --------------------------------------------------------------------
-export([
	set_state/2
		]).
    
%% --------------------------------------------------------------------
%% Internal exports
%% --------------------------------------------------------------------

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% --------------------------------------------------------------------
%% Record definitions
%% --------------------------------------------------------------------
-record(state, { root,
                 toc   % DETS {Key, content()}
                }).

-record(content, { pid,
                   mo,
                   server,
                   state
                  }).

%% --------------------------------------------------------------------
%% Macro definitions
%% --------------------------------------------------------------------
-define(NODE, rpc:node()).

-define(ROOT(State), State#state.root).
-define(TOC(State), State#state.toc).

-define(PID(Data), Data#content.pid).
-define(MO(Data), Data#content.mo).
-define(SERVER(Data), Data#content.server).
-define(STATE(Data), Data#content.state).

-define(TOC_FILE(State), ?ROOT(State) ++ "/toc.dets").

%% ====================================================================
%% External functions
%% ====================================================================

%% --------------------------------------------------------------------
%% @doc Starts the server.
%% @spec start_link() -> {ok, Pid} | {error, Reason}
%% @end
%% --------------------------------------------------------------------
start_link() ->
%% 	case config:get_parameter(?STORAGE_GS) of
%%         true  -> storage.ui.gs.pipes:start(), receive after 1000 -> true end;
%%         false -> true
%%     end,
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%------------------------------------------------------------------------------
%% add_resource(...) -> ok | {error, Reason}
%% 	Key       = atom()
%% 	MO        = atom()
%% 	Server    = {Host, Port}
%% 	Timestamp = {MegaSecs, Secs, MicroSecs}
%%------------------------------------------------------------------------------
add_resource(MO, Server) ->
    add_resource(MO, MO, Server).

add_resource(Key, MO, Server) ->
    gen_server:call(?MODULE, {add_resource, Key, MO, Server}).

%%------------------------------------------------------------------------------
%% cancel_resource(...) -> ok | {error, Reason}
%% 	Key       = atom()
%% 	Timestamp = {MegaSecs, Secs, MicroSecs}
cancel_resource(Key) ->
    gen_server:call(?MODULE, {cancel_resource, Key}).

%%------------------------------------------------------------------------------
%% resource_state(Key) -> unknown | {ready, File} | pending | {downloading, Pos, ETA} | {error, Reason}
%% 	Key  = atom()
%%	Pos = int()
%%	ETA = int()
%%	File = string()
%%------------------------------------------------------------------------------
resource_state(Key) ->
    gen_server:call(?MODULE, {resource_state, Key}).

%%------------------------------------------------------------------------------
%% cache_state(...) -> {ok, [Property]}
%% 	Property  =   {size, int()}
%%                  | {free, int()}
%%                  | {contents, [Key, MO, Timestamp]}
%% 	Key       = atom()
%% 	MO        = atom()
%% 	Timestamp = {MegaSecs, Secs, MicroSecs}
%%------------------------------------------------------------------------------
cache_state() ->
    gen_server:call(?MODULE, {cache_state}).

set_state(Key, St) ->
    gen_server:call(?MODULE, {set_state, Key, St}).

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
    process_flag(trap_exit, true),
    monitor:notify(storage, info, "Initializing storage"),
    State0 = #state{ root = config:get_parameter(?STORAGE_ROOT) ++ "/files/" ++ util:a2l(?NODE) },
	util:mkdir(?ROOT(State0)),
	ok = dstate:set_merge(fun(Key, Value, [{Node, St, StInfo}]) ->
        					  NewValue = [{Node, St, StInfo} | lists:keydelete(Node, 1, Value)],
                              case check_conflicts(NewValue) of
                                  [] ->
                                      NewValue;
                                  Nodes ->
                                      lists:foldl(fun({TheNode, PipePid}, ValueIn) ->
                                          			  monitor:notify(storage, debug, io_lib:format("Conflict in ~p - ~p", [TheNode, Key])),
                                          			  catch rpc:call(TheNode, storage.storage_fsm, conflict, [Key, PipePid]),
													  lists:keydelete(TheNode, 1, ValueIn)
                                          		  end, NewValue, Nodes)
                              end
        				  end),
	ok = dstate:set_del(fun(_Key, Value, Info) ->
        					case Info of
                                none ->
                                    delete;
                                Node ->
                                    case lists:keydelete(Node, 1, Value) of
                                        [] ->
                                            delete;
                                        NewValue ->
                                            NewValue
									end
							end
						end),
	case dets:open_file(?TOC_FILE(State0), [{type, set}, {auto_save, 30000}]) of
		{ok, Toc} ->
            Contents = dets:traverse(Toc, fun({Key, Data}) ->
                                              {ok, Pid} = storage_fsm:start_link([Key, ?MO(Data), ?ROOT(State0), ?SERVER(Data), ?STATE(Data)]),
                                              {continue, {Key, Data#content{ pid = Pid }}}
                                          end),
            lists:foreach(fun({Key, Data}) ->
                              ok = dets:insert(Toc, {Key, Data})
                          end, Contents),
			{ok, State0#state{ toc = Toc }};
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
handle_call({add_resource, Key, MO, Server}, _From, State) ->
    {ok, Result, NewState} = add_resource(State, Key, MO, Server),
    {reply, Result, NewState};

handle_call({cancel_resource, Key}, _From, State) ->
    {ok, Result, NewState} = cancel_resource(State, Key),
    {reply, Result, NewState};

handle_call({resource_state, Key}, _From, State) ->
    {ok, Result, NewState} = resource_state(State, Key),
    {reply, Result, NewState};

handle_call({cache_state}, _From, State) ->
    {ok, Result, NewState} = cache_state(State),
    {reply, Result, NewState};

handle_call({set_state, Key, St}, _From, State) ->
    {ok, Result, NewState} = set_state(State, Key, St),
    {reply, Result, NewState};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% --------------------------------------------------------------------
%% Function: handle_cast/2
%% Description: Handling cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%% --------------------------------------------------------------------
%% Function: handle_info/2
%% Description: Handling all non call/cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_info({'EXIT', _From, normal}, State) ->
    {noreply, State};

handle_info({'EXIT', From, Reason}, State) ->
    [{Key, Data}] = dets:traverse(?TOC(State), fun({Key, Data}) ->
        										   case ?PID(Data) of
                                       				   From ->
                                                 		   {done, {Key, Data}};
                                                       _ ->
                                                           continue
                                                   end
                                               end),
    monitor:notify(storage, vdebug, io_lib:format("[~p - ~p] Exits with reason ~p", [?NODE, Key, Reason])),
    {ok, Pid} = storage_fsm:start_link([Key, ?MO(Data), ?ROOT(State), ?SERVER(Data), ?STATE(Data)]),
    ok = dets:insert(?TOC(State), {Key, Data#content{ pid = Pid }}),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

%% --------------------------------------------------------------------
%% Function: terminate/2
%% Description: Shutdown the server
%% Returns: any (ignored by gen_server)
%% --------------------------------------------------------------------
terminate(_Reason, State) ->
    dets:close(?TOC(State)),
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

add_resource(State, Key, MO, Server) ->
    monitor:notify(storage, info, io_lib:format("[~p] Adding ~p (MO ~p) from ~p", [?NODE, Key, MO, Server])),
    case dets:lookup(?TOC(State), Key) of
        [{Key, _Data}] ->
            {ok, ok, State};
        _ ->
            Data = #content{ pid 	  = nil,
                             mo       = MO,
                             server   = Server,
                             state    = ?PENDING
        				    },
            {ok, Pid} = storage_fsm:start_link([Key, MO, ?ROOT(State), Server, ?PENDING]),
			ok = dets:insert(?TOC(State), {Key, Data#content{ pid = Pid }}),
			{ok, ok, State}
    end.

cancel_resource(State, Key) ->
    monitor:notify(storage, info, io_lib:format("[~p] Cancelling ~p", [?NODE, Key])),
    case dets:lookup(?TOC(State), Key) of
        [{Key, _Data}] ->
            ok = storage_fsm:cancel(Key),
            ok = dets:delete(?TOC(State), Key),
            {ok, ok, State};
        _ ->
            {ok, {error, not_found}, State}
    end.

resource_state(State, Key) ->
	case dets:lookup(?TOC(State), Key) of
        [{Key, _Data}] ->
            St = storage_fsm:state(Key),
            {ok, St, State};
        _ ->
            {ok, {error, not_found}, State}
    end.

cache_state(State) ->
    Contents = dets:foldl(fun({Key, Data}, Acc) ->
                              [{Key, ?MO(Data), ?SERVER(Data), ?STATE(Data)}|Acc]
                          end, [], ?TOC(State)),
    {ok, {ok, Contents}, State}.

set_state(State, Key, St) ->
    case dets:lookup(?TOC(State), Key) of
        [{Key, Data}] ->
            monitor:notify(storage, vdebug, io_lib:format("[~p] Setting state ~p to ~p", [?NODE, St, Key])),
    		ok = dets:insert(?TOC(State), {Key, Data#content{ state = St }}),
            {ok, ok, State};
		_ ->
            {ok, {error, not_found}, State}
    end.

% Conflicts

check_conflicts(Copies) ->
    util:shake(lists:usort(check_multiple_downloads(Copies) ++
                           check_downloads_ready(Copies) ++
                           check_cycles(Copies))).

check_multiple_downloads(Copies) ->
    case [{Node, StInfo} || {Node, St, StInfo} <- Copies, St == ?DOWNLOADING] of
        [] ->
            [];
        [_] ->
            [];
        Nodes ->
            monitor:notify(storage, vdebug, "Conflict: multiple downloads"),
            [{Node, PipePid} || {Node, PipePid} <- tl(util:shake(Nodes))]
    end.

check_downloads_ready(Copies) ->
    case [Node || {Node, St, _StInfo}  <- Copies, St == ?READY] of
        [] ->
            [];
        _ ->
            monitor:notify(storage, vdebug, "Conflict: downloads ready"),
            [{Node, PipePid} || {Node, St, PipePid}  <- Copies, St == ?DOWNLOADING]
    end.

check_cycles(Copies) ->
    Transfers = [ {Node, StInfo} || {Node, St, StInfo} <- Copies, St == ?TRANSFERRING ],
    lists:foldl(fun({Node, _}, AccIn) ->
                     case do_check_cycles(Node, Copies, Transfers, []) of
                         [] ->
                             AccIn;
                         Nodes ->
                             Nodes ++ AccIn
                     end
                end, [], Transfers).

do_check_cycles(Node, Copies, Transfers, Path) ->
    case lists:keymember(Node, 1, Path) of
        true ->
            monitor:notify(storage, vdebug, "Conflict: cycle"),
            Path;
        false ->
            case lists:keysearch(Node, 1, Transfers) of
                {value, {Node, {FromNode, PipePid}}} ->
                    do_check_cycles(FromNode, Copies, Transfers, [{Node, PipePid} | Path]);
                _ ->
                    []
            end
    end.
