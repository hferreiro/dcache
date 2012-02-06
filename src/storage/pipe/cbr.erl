%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : Constant bitrate pipe (from VoDKA project)
%%%-----------------------------------------------------------------------------

-module(storage.pipe.cbr).

-import(erlang).
-import(storage.util.proplist).

-include("ds_info.hrl").
-include("pipe.hrl").

%% API
-export([start/2, start/3, start_link/2, start_link/3]).

%% Internal API
-export([init/3]).

-define(SLEEP_TIME, 100). % msecs

-record(pipe_state, { bitrate,
                      pos,
                      initime,
                      notify_pos, %% trigger notification when Pos > notify_pos
                      notify_fun  %% when Pos > notify_pos apply notify_fun()
                    }).

%%%-----------------------------------------------------------------------------
%%% API
%%%-----------------------------------------------------------------------------

start(DS, DD) ->
    start(DS, DD, ?DEFAULT_PIPE_OPTIONS).

start(DS, DD, Options) ->
    spawn(?MODULE, init, [DS, DD, Options]).

start_link(DS, DD) ->
    start_link(DS, DD, ?DEFAULT_PIPE_OPTIONS).

start_link(DS, DD, Options) ->
    spawn_link(?MODULE, init, [DS, DD, Options]).

%%%-----------------------------------------------------------------------------
%%% Internal implementation
%%%-----------------------------------------------------------------------------

%%
%%
%%
init({DS_module, DS_initparam}, {DD_module, DD_initparam}, Options) ->
    %% Notify
    {Mon, Notify} = Options#pipe_options.notify,
    {NotifyPos, NotifyFun} = Options#pipe_options.trigger,
    BitRate = case Options#pipe_options.policy of
		  normal            -> inf;
		  {cbr, BR}         -> BR; 
                  {range, _, BRMax} -> BRMax
	      end,
    Mon:Notify(pipe, init, Options),
    Mon:Notify(pipe, bitrate, BitRate),
    %% Do it
    case catch DS_module:init(DS_initparam, Options#pipe_options.range) of
	{ok, DS_info, DS_state0} ->
            Mon:Notify(pipe, size, ?DS_SIZE(DS_info)),
	    Mon:Notify(pipe, name, ?DS_NAME(DS_info)),
	    Mon:Notify(pipe, range, ?DS_RANGE(DS_info)),
	    case catch DD_module:init(DS_info, DD_initparam) of
		{ok, DD_state0} ->
		    case catch pipe_while(DS_info, DS_module, DS_state0, DD_module, DD_state0, ntfy_init(Options),
                                          #pipe_state{ bitrate    = BitRate,
                                                       pos        = 0,
                                                       initime    = epoch_secs(),
                                                       notify_pos = NotifyPos,
                                                       notify_fun = NotifyFun}) of
			{ok, DS_statef, DD_statef} ->
                            R1 = DS_module:done(DS_statef),
			    R2 = DD_module:done(DD_statef),
                            case R1 of
                                ok ->
                                    case R2 of
                                        ok ->
                                            Mon:Notify(pipe, done, {ok, ok}),
                                            true;
                                        Error ->
                                            abort(Mon, Notify, Error)
                                    end;
                                Error ->
                                    abort(Mon, Notify, Error)
                            end;
			Error ->
                            abort(Mon, Notify, Error)
		    end;
		Error ->
		    ok = DS_module:abort(DS_state0),
                    abort(Mon, Notify, Error)
	    end;
	Error ->
            abort(Mon, Notify, Error)
    end.

%%
%%
%%
pipe_while(DS_info, DS_module, DS_state, DD_module, DD_state, MonInfo, PipeState) ->
    CurSec = epoch_secs(),
    Pos = PipeState#pipe_state.pos,
    BitRate = PipeState#pipe_state.bitrate,
    IniTime = PipeState#pipe_state.initime,
    NewPipeState = if
		       PipeState#pipe_state.notify_pos < Pos ->
			   (PipeState#pipe_state.notify_fun)(),
			   PipeState#pipe_state{notify_pos=inf};
		       true ->
			   PipeState
		   end,
    Target = case BitRate of
		 inf -> inf;
		 _   -> round( (CurSec-IniTime) * BitRate / 8)  % in Bytes
	     end,
    if
	(Target < Pos)  ->
	    receive after round(((Pos - Target)*8000/BitRate))  -> ok end,
	    %receive after ?SLEEP_TIME -> ok end,
	    pipe_while(DS_info, DS_module, DS_state, DD_module, DD_state, MonInfo,NewPipeState);
	true -> 
	    case catch DS_module:read(DS_state) of
		{ok, Data, DS_statenext} ->
		    case catch DD_module:write(Data, DD_state) of 
			{ok, DD_statenext} ->
			    NewMonInfo = ntfy(DS_info, Pos, size(Data), IniTime, CurSec, MonInfo),
			    pipe_while(DS_info, DS_module, DS_statenext, DD_module, DD_statenext, NewMonInfo, NewPipeState#pipe_state{pos=Pos+size(Data)});
			Error ->
			    ok = DS_module:abort(DS_statenext),
			    Error
		    end;
		{done, DS_statef} ->
		    ntfy_done(MonInfo),
		    {ok, DS_statef, DD_state};
		Error ->
		    ok = DD_module:abort(DD_state),
		    Error
	    end
    end.

%%
%% try to accumulate all the transfers performed within a second to avoid
%% too many notifications...
%%
ntfy_init(Options) ->
    {_, S, _} = erlang:now(),
    {Mon, Notify} = Options#pipe_options.notify,
    {0, S, {Mon, Notify}}.

%%
%%
%%
ntfy(DS_info, Pos, Size, IniTime, CurSec, {AccSize, S, MonInfo = {Mon, Notify}}) ->
    {_, S2, _} = erlang:now(),
    if
	S == S2 -> {Size+AccSize, S, MonInfo};
	true    ->
	    Mon:Notify(pipe, transfer, Size+AccSize),
            case Pos of
                0 -> true;
                _ -> Mon:Notify(pipe, progress, {Pos / ?DS_LENGTH(DS_info), (((?DS_LENGTH(DS_info)-Pos)*(CurSec-IniTime))/Pos)})
            end,
	    {0, S2, MonInfo}
    end.

%%
%%
%%
ntfy_done({Size, _, {Mon, Notify}}) when Size > 0 ->
    Mon:Notify(pipe, transfer, Size);
ntfy_done(_) ->
    ok.

%%
%%
%%
epoch_secs() ->
    {MegaSec, Sec, _} = erlang:now(),
    MegaSec * 1000000 + Sec.

%%
%%
%%
abort(Mon, Notify, {error, Reason}) ->
    Mon:Notify(pipe, abort, Reason),
    exit(Reason);
abort(Mon, Notify, Error) ->
    Mon:Notify(pipe, abort, Error),
    exit(Error).
