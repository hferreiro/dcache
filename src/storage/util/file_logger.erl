%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : Basic event file logger (from ARMISTICE)
%%%-----------------------------------------------------------------------------

-module(storage.util.file_logger).
-behaviour(gen_server).

-import(lists).
-import(file).
-import(erlang).
-import(io).
-import(io_lib).
-import(gen_server).
-import(calendar).
-import(storage.util.config).
-import(storage.util.monitor).
-import(storage.util.util).

-include("monitor.hrl").
-include("config.hrl").

%% API
-export([start_link/0]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, { log_file_handle,  %% Log file handler
                 event_types }).   %% [Event types to be logged] | all

%%%-----------------------------------------------------------------------------
%%% API
%%%-----------------------------------------------------------------------------

%%
%%
%%
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%%-----------------------------------------------------------------------------
%%% gen_server interface
%%%-----------------------------------------------------------------------------

%%
%%
%%
init(_) ->
    FileName = config:get_parameter(?STORAGE_ROOT) ++ "/log/storage.log",
    case file:open(FileName, [write, append]) of
        {ok, Handle} ->
            State0 = #state{ log_file_handle = Handle,
                             event_types     = config:get_parameter(?FILELOG_EVENTTYPES, all)
                           },
            do_log(Handle, startup),
            do_register(State0#state.event_types),
            {ok, State0};
        {error, Reason} ->
            {stop, Reason}
    end.

%%
%%
%%
%% handle_call(Request, From, State)
handle_call(_, _, State) ->
    {reply, unknown_request, State}.

%%
%%
%%
%% handle_cast(Msg, State)
handle_cast(_, State) ->
    {noreply, State}.

%%
%%
%%
handle_info({notify, E}, State) ->    
    do_log(State#state.log_file_handle, E),
    {noreply, State};

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
    catch file:close(State#state.log_file_handle),
    {ok, State}.

%%%-----------------------------------------------------------------------------
%%% Internal implementation
%%%-----------------------------------------------------------------------------

%%
%%
%%
do_log(Handle, startup) ->
    write_log(Handle, erlang:localtime(), "-------------------------------------------------------------------------"),
    write_log(Handle, erlang:localtime(), "Starting up at " ++ atom_to_list(node()));

do_log(Handle, E) ->
    Message = case (E#event.event_type == info) or
                   (E#event.event_type == debug) or
                   (E#event.event_type == vdebug) of
                  true ->
                      io_lib:format("[~p][~p][~p] ~s", [E#event.process_id, E#event.process_type, E#event.event_type, E#event.data]);
                  false ->
                      io_lib:format("[~p][~p][~p] ~p", [E#event.process_id, E#event.process_type, E#event.event_type, E#event.data])
              end,
    write_log(Handle, calendar:now_to_local_time(E#event.timestamp), Message).

%%
write_log(Handle, {{Year, Month, Day}, {H, M, S}}, Message) ->
    io:fwrite(Handle, "[~2..0w/~2..0w/~4..0w ~2..0w:~2..0w:~2..0w] ~s~n", [Day,Month,Year,H,M,S,Message]).

%%
%%
%%
do_register(all) ->
    monitor:observer_register(node());
do_register(EventTypes) ->
    monitor:observer_register(node(), EventTypes).
