%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : Wrapper for all pipes (from VoDKA project)
%%%-----------------------------------------------------------------------------

-module(storage.pipe.pipe).

-include("pipe.hrl").

-export([start/2, start/3, start_link/2, start_link/3]).

-export([pipe_options_default/0]).

%%
%% DS behaviour (callbacks)
%% ------------------------
%%
%% DS:init(DS_initparam, Range)  -> {ok, DS_info, DS_state}
%%                                | {error, Reason}
%%
%% DS:read(DS_State)      -> {ok, Data, DS_state} 
%%                         | {error, Reason }
%%                         | {done, DS_doneparam}
%%
%% DS:done(DS_doneparam)  -> ok
%%                         | {error, Reason}
%%
%% DS:abort(DS_state)     -> ok
%%
%%
%% DD behaviour (callbacks)
%% ------------------------
%%
%% DD:init(DS_info, DD_initparam)  -> {ok, DD_state}
%%                                  | {error, Reason}
%%
%% DD:write(Data, DD_State)        -> {ok, DD_state} 
%%                                  | {error, Reason} 
%%
%% DD:done(DD_State)               -> ok
%%                                  | {error, Reason}
%%
%% DD:abort(DD_state)              -> ok
%%

%%
%%
%%
pipe_options_default() ->
    #pipe_options{}.

%%
%% start(DS, DD) -> Pid
%%
%%    DS = {DS_module, DS_initparam}   
%%
%%          data source module implementing {init, read, done} callbacks 
%%          and its initialization parameter
%%
%%    DD = {DD_module, DD_initparam}   
%%
%%          data destination module implementing {init, write, done) 
%%          callbacks and its initialization parameter
%%
%%    Pid = pid()
%%
%%          newly created process that performs transfer from DS -> DD
%%
start(DS, DD) ->
    start(DS, DD, ?DEFAULT_PIPE_OPTIONS).

%%
%% start(DS, DD, Options) -> Pid
%%
%%    Options = #pipe_options
%%
%%          Specific options for the pipe (see include file pipe_options.hrl)
%%
start(DS, DD, Options) ->
    (get_pipe_module(Options)):start(DS, DD, Options).

%%
%% start_link(DS, DD) -> Pid
%%
%%    same as start/2, but linking pipe to the calling process
%%
start_link(DS, DD) ->
    start_link(DS, DD, ?DEFAULT_PIPE_OPTIONS).

%%
%% start_link(DS, DD, Options) -> Pid
%%
%%    same as start/3, but linking pipe to the calling process
%%
start_link(DS, DD, Options) ->
    (get_pipe_module(Options)):start_link(DS, DD, Options).

%%
%%
%%
get_pipe_module(Options) ->
    case Options#pipe_options.policy of
	_ -> storage.pipe.cbr
    end.
