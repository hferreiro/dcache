%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : Basic pipe (from VoDKA project)
%%%-----------------------------------------------------------------------------

-module(storage.pipe.simple).

-include("pipe.hrl").

%% API
-export([start/2, start/3, start_link/2, start_link/3]).

%% Internal API
-export([init/3]).

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
    {ok, DS_info, DS_state0} = DS_module:init(DS_initparam, Options#pipe_options.range),
    {ok, DD_state0} = DD_module:init(DS_info, DD_initparam),
    {DS_statef, DD_statef} = pipe_while(DS_module, DS_state0, DD_module, DD_state0),
    ok = DS_module:done(DS_statef),
    ok = DD_module:done(DD_statef).

%%
%%
%%
pipe_while(DS_module, DS_state, DD_module, DD_state) ->
    case DS_module:read(DS_state) of
	{ok, Data, DS_statenext} ->
	    {ok, DD_statenext} = DD_module:write(Data, DD_state),
	    pipe_while(DS_module, DS_statenext, DD_module, DD_statenext);
	{done, DS_statef} ->
	    {DS_statef, DD_state}
    end.
