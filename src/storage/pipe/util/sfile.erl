%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : -
%%%-----------------------------------------------------------------------------

-module(storage.pipe.util.sfile).
-behaviour(gen_server).

-import(file).
-import(filename).
-import(lists).
-import(io_lib).
-import(gen_server).
-import(storage.util.monitor).
-import(storage.util.util).

-include_lib("kernel/include/file.hrl").
-include("util.hrl").
-include("config.hrl").

%% API
-export([start_link/0, open/2, read_file_info/1, read/2, write/2, position/2, close/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, { files, % [{File, IdAcc, IoDevice}] 
                 ios    % [{ IoDevice, Size, IoState,         IoState = oppening | open | clossing
                        %    [{Id, Mode, Position, Pid}],     Mode = read (n) | write (1)
                        %    [{Pid, Ref}] }]                  Blocked readers
               }).

%%%-----------------------------------------------------------------------------
%%% API (file proxy)
%%%-----------------------------------------------------------------------------

%%
%%
%%
start_link() ->
    util:start_link_gen_server({local, ?MODULE}, ?MODULE, [], []).

%%
%% Mode = {read, Size} | {write, Size}
%%
open(Filename, Mode) ->
    gen_server:call(?MODULE, {open, Filename, Mode, self()}, ?GENSERVER_TIMEOUT).

%%
%%
%%
read_file_info(Filename) ->
    gen_server:call(?MODULE, {read_file_info, Filename}, ?GENSERVER_TIMEOUT).

%%
%%
%%
read(SIoDevice, Number) ->
    blocking_call({read, SIoDevice, Number, self()}).

%%
%%
%%
write(SIoDevice, Bytes) ->
    gen_server:call(?MODULE, {write, SIoDevice, Bytes}, ?GENSERVER_TIMEOUT).

%%
%%
%%
position(SIoDevice, Location)  ->
    gen_server:call(?MODULE, {position, SIoDevice, Location}, ?GENSERVER_TIMEOUT).

%%
%%
%%
close(SIoDevice) ->
    gen_server:call(?MODULE, {close, SIoDevice}, ?GENSERVER_TIMEOUT).

%%
blocking_call(Request) ->
    case gen_server:call(?MODULE, Request, ?GENSERVER_TIMEOUT) of
	{wait, Ref} ->
	    receive
		Ref -> blocking_call(Request)
	    end;
        _Else -> _Else
    end.

%%%-----------------------------------------------------------------------------
%%% gen_server interface
%%%-----------------------------------------------------------------------------

%%
%%
%%
init(_) ->
    process_flag(trap_exit, true),
    monitor:notify(sfile, info, io_lib:format("Initializing sfile", [])),
    State0 = #state{ files = [],
                     ios   = [] },
    {ok, State0}.

%%
%%
%%
handle_call({open, Filename, Mode, Pid}, _, State) ->
    {ok, Reply, NewState} = open(State, Filename, Mode, Pid),
    {reply, Reply, NewState};

handle_call({read_file_info, Filename}, _, State) ->
    {ok, Reply, NewState} = read_file_info(State, Filename),
    {reply, Reply, NewState};

handle_call({read, SIoDevice, Number, Pid}, _, State) ->
    {ok, Reply, NewState} = read(State, SIoDevice, Number, Pid),
    {reply, Reply, NewState};

handle_call({write, SIoDevice, Bytes}, _, State) ->
    {ok, Reply, NewState} = write(State, SIoDevice, Bytes),
    {reply, Reply, NewState};

handle_call({position,SIoDevice, Location}, _, State) ->
    {ok, Reply, NewState} = position(State, SIoDevice, Location),
    {reply, Reply, NewState};

handle_call({close, SIoDevice}, _, State) ->
    {ok, Reply, NewState} = close(State, SIoDevice),
    {reply, Reply, NewState};

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
handle_info({'EXIT', From, _}, State) ->
    NewState = lists:foldl(fun({IoDevice, _, _, Ids, _}, StateIn1) ->
                               lists:foldl(fun({Id, _, _, Pid}, StateIn2) ->
                                               case Pid of
                                                   From ->
                                                       case catch close(StateIn2, {Id, IoDevice}) of
                                                           {ok, ok, StateOut} -> StateOut;
                                                           _                  -> StateIn2
                                                       end;
                                                   _ -> StateIn2
                                               end
                                           end, StateIn1, Ids)
                           end, State, State#state.ios),
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
%%% Internal implementation
%%%-----------------------------------------------------------------------------

%%
%%
%%
open(State, Filename, Mode, Pid) ->
    AbsFilename = filename:absname(Filename),
    case lists:keysearch(AbsFilename, 1, State#state.files) of
        {value, {AbsFilename, IdAcc, IoDevice}} ->
            {value, {IoDevice, Size, IoState, Ids, Blocked}} = lists:keysearch(IoDevice, 1, State#state.ios),
            case Mode of
                {write, Size} ->
                    case lists:keymember(write, 2, Ids) of
                        false -> do_open(State, AbsFilename, IdAcc, write, Pid, IoDevice, open, Size, Ids, Blocked);
                        true  -> {ok, {error, resource_busy}, State}
                    end;
                {read, Size}  -> do_open(State, AbsFilename, IdAcc, read, Pid, IoDevice, IoState, Size, Ids, Blocked);
                {_, _}        -> {ok, {error, incongruous_size}, State}
            end;
        _ ->
            case catch do_open(Filename, Mode) of
                {ok, IoDevice, TheMode, Size, IoState} ->
                    SIoDevice = {1, IoDevice},
                    NewState = State#state{ files = [{AbsFilename, 1, IoDevice} | State#state.files],
                                            ios   = [{IoDevice, Size, IoState, [{1, TheMode, 0, Pid}], []} | State#state.ios] },
                    true = link(Pid),
                    {ok, {ok, SIoDevice}, NewState};
                {error, Reason} ->
                    {ok, {error, Reason}, State}
            end
    end.

%%
do_open(Filename, Mode) ->
    {TheMode, Size, IoState} = case Mode of
                                   {read, S}  -> {read, S, openning};
                                   {write, S} -> {write, S, open};
                                   _          -> throw({error, unknown_mode})
                               end,
    case file:open(Filename, [read, write, raw, binary]) of
        {ok, IoDevice}  -> {ok, IoDevice, TheMode, Size, IoState};
        {error, Reason} -> {error, Reason}
    end.

%%
do_open(State, AbsFilename, IdAcc, Mode, Pid, IoDevice, IoState, Size, Ids, Blocked) ->
    SIoDevice = {IdAcc+1, IoDevice},
    NewState = State#state{ files = lists:keyreplace(AbsFilename, 1, State#state.files, {AbsFilename, IdAcc+1, IoDevice}),
                            ios   = lists:keyreplace(IoDevice, 1, State#state.ios, {IoDevice, Size, IoState, [{IdAcc+1, Mode, 0, Pid} | Ids], Blocked}) },
    true = link(Pid),
    {ok, {ok, SIoDevice}, NewState}.

%%
%%
%%
read_file_info(State, Filename) ->
    Reply = case lists:keysearch(filename:absname(Filename), 1, State#state.files) of
                {value, {_, _, IoDevice}} ->
                    {value, {_, Size, _, _}} = lists:keysearch(IoDevice, 1, State#state.ios),
                    case file:read_file_info(Filename) of
                        {ok, FileInfo}  -> {{ok, FileInfo#file_info{ size = Size }}, State};
                        {error, Reason} -> {{error, Reason}, State}
                    end;
                _ ->
                    {file:read_file_info(Filename), State}
            end,
    {ok, Reply, State}.

%%
%%
%%
read(State, {Id, IoDevice}, Number, CallPid) ->
    case lookup(State, Id, IoDevice) of
        {ok, {IoDevice, Size, IoState, Ids, Blocked}, {Id, Mode, Position, Pid}} ->
            file:sync(IoDevice),
            case file:position(IoDevice, Position) of
                {ok, _} ->
                    case file:read(IoDevice, Number) of
                        {ok, Data} ->
                            NewIds = lists:keyreplace(Id, 1, Ids, {Id, Mode, Position + size(Data), Pid}),
                            NewState = State#state{ ios = lists:keyreplace(IoDevice, 1, State#state.ios, {IoDevice, Size, IoState, NewIds, Blocked}) },
                            {ok, {ok, Data}, NewState};
                        _Else ->
                            case Position >= Size of
                                true  -> {ok, eof, State};
                                false ->
                                    case IoState of
                                        clossing ->
                                            {ok, _Else, State};
                                        _ ->
                                            Ref = now(),
                                            { ok,
                                              {wait, Ref},
                                              State#state{ ios = lists:keyreplace(IoDevice, 1, State#state.ios, {IoDevice, Size, IoState, Ids, [{CallPid, Ref} | Blocked]}) } }
                                    end
                            end
                    end;
                {error, Reason} ->
                    {ok, {error, Reason}, State}
            end;
       {error, Reason} ->
           {ok, {error, Reason}, State}
    end.

%%
%%
%%
write(State, {Id, IoDevice}, Bytes) ->
    case lookup(State, Id, IoDevice) of
        {ok, {IoDevice, _, openning, _, _}, {Id, _, _, _}} ->
            {ok, {error, ebadf}, State};
        {ok, {IoDevice, _, clossing, _, _}, {Id, _, _, _}} ->
            {ok, {error, ebadf}, State};
        {ok, {IoDevice, Size, open, Ids, Blocked}, {Id, Mode, Position, Pid}} ->
            case file:position(IoDevice, Position) of
                {ok, _} ->
                    case file:write(IoDevice, Bytes) of
                        ok ->
                            ok = wakeup(Blocked),
                            NewIds = lists:keyreplace(Id, 1, Ids, {Id, Mode, Position + size(Bytes), Pid}),
                            NewState = State#state{ ios = lists:keyreplace(IoDevice, 1, State#state.ios, {IoDevice, Size, open, NewIds, []}) },
                            {ok, ok, NewState};
                        {error, Reason} ->
                            {ok, {error, Reason}, State}
                    end;
                {error, Reason} ->
                    {ok, {error, Reason}, State}
            end;
       {error, Reason} ->
           {ok, {error, Reason}, State}
    end.

%%
%%
%%
position(State, SIoDevice, {bof, Offset}) ->
    position(State, SIoDevice, Offset);

position(State, _, {cur, _}) ->
    {ok, {error, not_implemented}, State};

position(State, _, {eof, _}) ->
    {ok, {error, not_implemented}, State};

position(State, SIoDevice, bof) ->
    position(State, SIoDevice, 0);

position(State, _, cur) ->
    {ok, {error, not_implemented}, State};
                                 
position(State, _, eof) ->
    {ok, {error, not_implemented}, State};

position(State, {Id, IoDevice}, Offset) ->
    case lookup(State, Id, IoDevice) of
       {ok, {IoDevice, Size, IoState, Ids, Blocked}, {Id, Mode, _, Pid}} ->
           case Offset =< Size of
               true ->
                   NewIds = lists:keyreplace(Id, 1, Ids, {Id, Mode, Offset, Pid}),
                   NewState = State#state{ ios = lists:keyreplace(IoDevice, 1, State#state.ios, {IoDevice, Size, IoState, NewIds, Blocked}) },
                   {ok, {ok, Offset}, NewState};
               false ->
                   {ok, {error, einval}, State}
           end;
       {error, Reason} ->
           {ok, {error, Reason}, State}
    end.

%%
%%
%%
close(State, {Id, IoDevice}) ->
    case lookup(State, Id, IoDevice) of
       {ok, {IoDevice, Size, IoState, Ids, Blocked}, {Id, Mode, _, _}} ->
           case lists:keydelete(Id, 1, Ids) of
               [] ->
                   case file:close(IoDevice) of
                       ok ->
                           NewState = State#state{ files = lists:keydelete(IoDevice, 3, State#state.files),
                                                   ios   = lists:keydelete(IoDevice, 1, State#state.ios) },
                           {ok, ok, NewState};
                       {error, Reason} ->
                           {ok, {error, Reason}, State}
                   end;
               NewIds ->
                   NewState = case Mode of
                                  write ->
                                      wakeup(Blocked),
                                      State#state{ ios = lists:keyreplace(IoDevice, 1, State#state.ios, {IoDevice, Size, clossing, NewIds, []}) };
                                  read ->
                                      State#state{ ios = lists:keyreplace(IoDevice, 1, State#state.ios, {IoDevice, Size, IoState, NewIds, Blocked}) }
                              end,
                   {ok, ok, NewState}
           end;
       {error, Reason} ->
           {ok, {error, Reason}, State}
    end.

%%
lookup(State, Id, IoDevice) ->
    case lists:keysearch(IoDevice, 1, State#state.ios) of
       {value, {IoDevice, _, _, Ids, _}=TheIo} ->
           case lists:keysearch(Id, 1, Ids) of
               {value, {Id, _, _, _}=TheId} -> {ok, TheIo, TheId};
               _                            -> {error, ebadf}
           end;
       _ -> {error, ebadf}
    end.

%%
wakeup(Blocked) ->
    lists:foreach(fun({Pid, Ref}) ->
                      Pid ! Ref
                  end, Blocked),
    ok.
