-module(storage.storage_fsm).
-behaviour(gen_fsm).

-import(gen_fsm).
-import(file).
-import(io_lib).
-import(lists).

-import(storage.dstate).
-import(storage.pipe.pipe).
-import(storage.storage).
-import(storage.util.config).
-import(storage.util.monitor).
-import(storage.util.util).

%% --------------------------------------------------------------------
%% Include files
%% --------------------------------------------------------------------
-include("config.hrl").
-include("pipe.hrl").
-include("storage.hrl").

%% --------------------------------------------------------------------
%% External exports
%% --------------------------------------------------------------------
-export([
	start_link/1,
    state/1,
    cancel/1,
    conflict/2
		]).

%% --------------------------------------------------------------------
%% Internal exports
%% --------------------------------------------------------------------
-export([
	rpc_ping/1,
    rpc_transfer/3
		]).

%% gen_fsm callbacks
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4, 
         ready/2, pending/2,
         ready/3, pending/3, downloading/3, transferring/3, error/3]).

%% --------------------------------------------------------------------
%% Record definitions
%% --------------------------------------------------------------------
-record(data, { key,
				mo,
                path,
				info,
                progress,
                server,
				transfers
               }).

%% --------------------------------------------------------------------
%% Macro definitions
%% --------------------------------------------------------------------
-define(FSM(Key), util:a2a(util:a2l(?MODULE) ++ util:a2l(Key))).

-define(NODE, rpc:node()).

-define(KEY(Data), Data#data.key).
-define(MO(Data), Data#data.mo).
-define(PATH(Data), Data#data.path).
-define(INFO(Data), Data#data.info).
-define(PROGRESS(Data), Data#data.progress).
-define(SERVER(Data), Data#data.server).
-define(TRANSFERS(Data), Data#data.transfers).

-define(FSM_TIMEOUT, 6000).
-define(PING_TIMEOUT, 700).

%% ====================================================================
%% External functions
%% ====================================================================

start_link([Key|_] = Data) ->
    gen_fsm:start_link({local, ?FSM(Key)}, ?MODULE, Data, []).

state(Key) ->
    gen_fsm:sync_send_event(?FSM(Key), state).

cancel(Key) ->
    gen_fsm:sync_send_event(?FSM(Key), cancel).

conflict(_Key, PipePid) ->
    exit(PipePid, conflict),
    ok.

rpc_ping(Key) ->
    gen_fsm:sync_send_event(?FSM(Key), ping).

rpc_transfer(Key, DD, Range) ->
    gen_fsm:sync_send_all_state_event(?FSM(Key), {transfer, DD, Range}).

%% ====================================================================
%% Server functions
%% ====================================================================

%% --------------------------------------------------------------------
%% Func: init/1
%% Returns: {ok, State, Data}          |
%%          {ok, State, Data, Timeout} |
%%          ignore                     |
%%          {stop, StopReason}
%% --------------------------------------------------------------------
init([Key, MO, Root, Server, State]) ->
    process_flag(trap_exit, true),
    monitor:notify(storage_fsm, info, io_lib:format("[~p] Initializing storage_fsm with Key '~p' and State ~p", [?NODE, Key, State])),
    monitor:observer_register(self(), node(), {type, pipe}, [progress]),
    Data0 = #data{ key       = Key,
                   mo        = MO,
				   path      = Root ++ "/" ++ util:a2l(Key),
                   info      = unknown,
                   progress  = {0, unknown},
                   server    = Server,
				   transfers = []
				  },
    case State of
		?READY ->
		    case util:file_size(?PATH(Data0)) of   
                {ok, _Size} ->
                    {ok, ready, Data0, ?FSM_TIMEOUT};
				_ ->
                    {ok, pending, Data0, ?FSM_TIMEOUT}
			end;
        ?ERROR ->
            ok = dstate:del(?KEY(Data0), ?NODE),
            {ok, error, Data0};
        _ ->
            {ok, pending, Data0, 0}
	end.

%% --------------------------------------------------------------------
%% Func: State/2
%% Returns: {next_state, NextState, NextData}          |
%%          {next_state, NextState, NextData, Timeout} |
%%          {stop, Reason, NewData}
%% --------------------------------------------------------------------
pending(timeout, Data) ->
    {ok, NextState, NewData} = do_pending(Data),
    {next_state, NextState, NewData}.

ready(timeout, Data) ->
    ok = dstate:put(?KEY(Data), [{?NODE, ?READY, true}]),
    {next_state, ready, Data#data{ info = true }}.

%% --------------------------------------------------------------------
%% Func: State/3
%% Returns: {next_state, NextState, NextData}            |
%%          {next_state, NextState, NextData, Timeout}   |
%%          {reply, Reply, NextState, NextData}          |
%%          {reply, Reply, NextState, NextData, Timeout} |
%%          {stop, Reason, NewData}                          |
%%          {stop, Reason, Reply, NewData}
%% --------------------------------------------------------------------
pending(ping, _From, Data) ->
    {reply, ok, pending, Data};
pending(state, _From, Data) ->
    {reply, {pending, true}, pending, Data};
pending(cancel, _From, Data) ->
    clean(Data),
    {stop, normal, ok, Data}.

downloading(ping, _From, Data) ->
    {reply, ok, downloading, Data};
downloading(state, _From, Data) ->
    {reply, {downloading, ?PROGRESS(Data)}, downloading, Data};
downloading(cancel, _From, Data) ->
    exit(?INFO(Data), kill),
    clean(Data),
    {stop, normal, ok, Data}.

transferring(ping, _From, Data) ->
    {reply, ok, transferring, Data};
transferring(state, _From, Data) ->
    {reply, {transferring, ?PROGRESS(Data)}, transferring, Data};
transferring(cancel, _From, Data) ->
    {PipePid, _} = ?INFO(Data),
	exit(PipePid, kill),
    clean(Data),
    {stop, normal, ok, Data}.

ready(ping, _From, Data) ->
    {reply, ok, ready, Data};
ready(state, _From, Data) ->
    {reply, {ready, ?PATH(Data)}, ready, Data};
ready(cancel, _From, Data) ->
    clean(Data),
    {stop, normal, ok, Data}.

error(ping, _From, Data) ->
    {reply, {error, not_found}, error, Data};
error(state, _From, Data) ->
    {reply, {error, ?INFO(Data)}, error, Data};
error(cancel, _From, Data) ->
    clean(Data),
    {stop, normal, ok, Data}.

%% --------------------------------------------------------------------
%% Func: handle_event/3
%% Returns: {next_state, NextState, NextData}          |
%%          {next_state, NextState, NextData, Timeout} |
%%          {stop, Reason, NewData}
%% --------------------------------------------------------------------
handle_event(_Event, State, Data) ->
    {next_state, State, Data}.

%% --------------------------------------------------------------------
%% Func: handle_sync_event/4
%% Returns: {next_state, NextState, NextData}            |
%%          {next_state, NextState, NextData, Timeout}   |
%%          {reply, Reply, NextState, NextData}          |
%%          {reply, Reply, NextState, NextData, Timeout} |
%%          {stop, Reason, NewData}                          |
%%          {stop, Reason, Reply, NewData}
%% --------------------------------------------------------------------
handle_sync_event({transfer, DD, Range}, _From, State, Data) ->
    {Reply, NewData} = transfer(Data, DD, Range),
    {reply, Reply, State, NewData};

handle_sync_event(_Event, _From, State, Data) ->
    {reply, {error, unknown_event}, State, Data}.

%% --------------------------------------------------------------------
%% Func: handle_info/3
%% Returns: {next_state, NextState, NextData}          |
%%          {next_state, NextState, NextData, Timeout} |
%%          {stop, Reason, NewData}
%% --------------------------------------------------------------------
handle_info({'EXIT', From, Reason}, State, Data) ->
    case lists:member(From, ?TRANSFERS(Data)) of
        true ->
			monitor:notify(storage_fsm, vdebug, io_lib:format("[~p - ~p] handle_exit - ~p (transfer_r)", [?NODE, ?KEY(Data), Reason])),
    		{next_state, State, Data#data{ transfers = lists:delete(From, ?TRANSFERS(Data)) }};
        false ->
            case handle_exit(State, Data, From, Reason) of
                {ok, NextState, NewData} ->
					{next_state, NextState, NewData};
				{stop, TheReason, NewData} ->
                    {stop, TheReason, NewData}
			end
	end;

handle_info({notify, {event, _, pipe, _Pid, progress, Progress}}, State, Data) ->
    {next_state, State, Data#data{ progress = Progress }};

handle_info(_Info, State, Data) ->
    {next_state, State, Data}.

%% --------------------------------------------------------------------
%% Func: terminate/3
%% Purpose: Shutdown the fsm
%% Returns: any
%% --------------------------------------------------------------------
terminate(_Reason, _State, _Data) ->
    ok.

%% --------------------------------------------------------------------
%% Func: code_change/4
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState, NewData}
%% --------------------------------------------------------------------
code_change(_OldVsn, State, Data, _Extra) ->
    {ok, State, Data}.

%% --------------------------------------------------------------------
%% Internal functions
%% --------------------------------------------------------------------

handle_exit(downloading, Data, From, Reason) ->
    case From == ?INFO(Data) of
        true ->
            do_handle_exit(Data, Reason);
        false ->
            monitor:notify(storage_fsm, vdebug, io_lib:format("[~p - ~p] Wrong exit signal: ~p from ~p", [?NODE, ?KEY(Data), Reason, From])),
            {ok, downloading, Data}
	end;

handle_exit(transferring, Data, From, Reason) ->
    {Pid, TState} = ?INFO(Data),
    case From == Pid of
        true ->
            monitor:notify(storage_fsm, vdebug, io_lib:format("[~p - ~p] Closing transfer ~p", [?NODE, ?KEY(Data), Pid])),
			catch (config:get_parameter(?TRANSFER_MOD)):done(TState),
            do_handle_exit(Data, Reason);
        false ->
            monitor:notify(storage_fsm, vdebug, io_lib:format("[~p - ~p] Wrong exit signal: ~p from ~p", [?NODE, ?KEY(Data), Reason, From])),
            {ok, transferring, Data}
    end;

handle_exit(State, Data, _From, _Reason) ->
    {ok, State, Data}.

do_handle_exit(Data, normal) ->
    monitor:notify(storage_fsm, debug, io_lib:format("[~p - ~p] handle_exit - normal", [?NODE, ?KEY(Data)])),
	ok = dstate:put(?KEY(Data), [{?NODE, ?READY, true}]),
	ok = storage:set_state(?KEY(Data), ?READY),
	{ok, ready, Data#data{ info = true }};

do_handle_exit(Data, {storage.pipe.ds.http_get, not_found}) ->
    monitor:notify(storage_fsm, debug, io_lib:format("[~p - ~p] handle_exit - not_found (~p)", [?NODE, ?KEY(Data), ?MO(Data)])),
	ok = dstate:del(?KEY(Data), ?NODE),
	ok = storage:set_state(?KEY(Data), ?ERROR),
	{ok, error, Data#data{ info = not_found }};

% reason = conflict | premature_end | timeout
do_handle_exit(Data, Reason) ->
    monitor:notify(storage_fsm, vdebug, io_lib:format("[~p - ~p] handle_exit - ~p (stop)", [?NODE, ?KEY(Data), Reason])), 
	{stop, Reason, Data}.

do_pending(Data) ->
    ok = storage:set_state(?KEY(Data), ?PENDING),
    ok = dstate:put(?KEY(Data), [{?NODE, ?PENDING, true}]),
    case get_node(?KEY(Data)) of
        {ok, Node} ->
            {ok, NextState, NewData} = do_transfer(Node, Data),
            {ok, NextState, NewData};
		_ ->
            {ok, NewData} = do_download(Data),
            {ok, downloading, NewData}
	end.

do_transfer(Node, Data) ->
    monitor:notify(storage_fsm, info, io_lib:format("[~p - ~p] Transferring from node ~p", [?NODE, ?KEY(Data), Node])),
    {TState, DS, RemoteDD} = (config:get_parameter(?TRANSFER_MOD)):init(config:get_parameter(?TRANSFER_ARGS)),
    DD = {storage.pipe.dd.sfile, ?PATH(Data)},
    Pid = pipe:start_link(DS, DD),
    case catch rpc:ecall(Node, ?MODULE, transfer, [?KEY(Data), RemoteDD, range(?PATH(Data))]) of
        ok ->
            ok = dstate:put(?KEY(Data), [{?NODE, ?TRANSFERRING, {Node, Pid}}]),
            ok = storage:set_state(?KEY(Data), ?TRANSFERRING),
            {ok, transferring, Data#data{ info = {Pid, TState} }};
        {'EXIT', nodedown} ->
            ok = dstate:del(?KEY(Data), Node),
            exit(Pid, kill),
            catch (config:get_parameter(?TRANSFER_MOD)):done(TState),
            do_pending(Data);
        {'EXIT', _Reason} ->
            exit(Pid, kill),
            catch (config:get_parameter(?TRANSFER_MOD)):done(TState),
            do_pending(Data)
    end.

transfer(Data, DD, Range) ->
    monitor:notify(storage_fsm, info, io_lib:format("[~p - ~p] Transferring", [?NODE, ?KEY(Data)])),
    DS = {storage.pipe.ds.sfile, {?PATH(Data), config:get_parameter(?TRANSFER_LAN_BLOCK)}},
    Pid = pipe:start_link(DS, DD, #pipe_options{ policy = config:get_parameter(?TRANSFER_LAN_POLICY),
                                           		 range  = Range }),
    {ok, Data#data{ transfers = [Pid | ?TRANSFERS(Data)] }}.

do_download(Data) ->
    monitor:notify(storage_fsm, info, io_lib:format("[~p - ~p] Downloading from server ~p", [?NODE, ?KEY(Data), ?SERVER(Data)])),
    DS = {storage.pipe.ds.http_get, util:http_url(?SERVER(Data), ?MO(Data))},
    DD = {storage.pipe.dd.sfile, ?PATH(Data)},
    Pid = pipe:start_link(DS, DD, #pipe_options{ policy = config:get_parameter(?TRANSFER_SERVER_POLICY),
                                                 range  = range(?PATH(Data)) }),
    ok = storage:set_state(?KEY(Data), ?DOWNLOADING),
	ok = dstate:put(?KEY(Data), [{?NODE, ?DOWNLOADING, Pid}]),
    {ok, Data#data{ info = Pid }}.

range(File) ->
    case util:file_size(File) of
        {ok, Size} ->
            monitor:notify(storage_fsm, debug, io_lib:format("[~p] Already downloaded ~p", [?NODE, Size])),
            {Size, inf};
        _ ->
            monitor:notify(storage_fsm, debug, io_lib:format("[~p] Getting complete file", [?NODE])),
            complete
    end.

get_node(Key) ->
    case dstate:get(Key) of
       {ok, Nodes} ->
           Ready = [Node || {Node, St, _StInfo} <- Nodes, Node /= ?NODE, St == ?READY],
           Downloading = [Node || {Node, St, _StInfo} <- Nodes, Node /= ?NODE, St == ?DOWNLOADING],
           Transferring = [Node || {Node, St, _StInfo} <- Nodes, Node /= ?NODE, St == ?TRANSFERRING],
           do_get_node(Key, util:shake(Ready) ++ util:shake(Downloading ++ Transferring));
       _ ->
           {error, not_found}
    end.

do_get_node(_, []) ->
    {error, not_found};

do_get_node(Key, [Node | Nodes]) ->
    case ping_and_update(Node, Key) of
        {ok, Node} ->
            {ok, Node};
        {error, not_found} ->
            do_get_node(Key, Nodes)
    end.

ping_and_update(Node, Key) ->
    case rpc:call(Node, ?MODULE, rpc_ping, [Key], ?PING_TIMEOUT) of
        ok ->
            {ok, Node};
        _  ->
            catch dstate:del(Key, Node),
			{error, not_found}
    end.

clean(Data) ->
    lists:foreach(fun(Pid) ->
        			exit(Pid, kill)
				  end, ?TRANSFERS(Data)),
    catch file:delete(?PATH(Data)),
	catch file:delete(?PATH(Data) ++ ".sfile"),
	ok = dstate:del(?KEY(Data), ?NODE).
