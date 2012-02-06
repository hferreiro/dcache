%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : - (from ARMISTICE)
%%%-----------------------------------------------------------------------------

-module(storage.util.config).
-behaviour(gen_server).

-import(erl_parse).
-import(erl_scan).
-import(file).
-import(gen_server).
-import(init).
-import(lists).
-import(regexp).

-import(storage.util.util).

-include("util.hrl").
-include("config.hrl").

%% API
-export([start_link/0, get_parameter/1, get_parameter/2, get_argument/2, update/0, get_all/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%%-----------------------------------------------------------------------------
%%% API
%%%-----------------------------------------------------------------------------

%%
%%
%%
start_link() ->
    util:start_link_gen_server({local, ?MODULE}, ?MODULE, [], []).

%%
%%
%%
get_parameter(ParameterName) ->
    case gen_server:call(?MODULE, {get_parameter, util:a2l(ParameterName)}, ?GENSERVER_TIMEOUT) of
        {error, Reason} -> throw({'EXIT', Reason});
        _Else           -> _Else
    end.

%%
%%
%%
get_parameter(ParameterName, Default) ->
    case catch gen_server:call(?MODULE, {get_parameter, util:a2l(ParameterName)}, ?GENSERVER_TIMEOUT) of
        {error, _} -> Default;
        _Else      -> _Else
    end.

%%
%%
%%
get_argument(Key, ParameterName) ->
    {ok, Opts} = init:get_argument(?CONFIG_FLAG),
    do_get_argument(Key, ParameterName, Opts).

%%
do_get_argument(Key, _, [[Key,V]|_])       -> util:a2i(V);
do_get_argument(Key, ParameterName, [_|T]) -> do_get_argument(Key, ParameterName, T);
do_get_argument(_, ParameterName, [])      -> get_parameter(ParameterName).

%%
%%
%%
get_all() ->
    gen_server:call(?MODULE, {get_all}, ?GENSERVER_TIMEOUT).

%%
%%
%%
update() ->
    gen_server:call(?MODULE, {update}, ?GENSERVER_TIMEOUT).

%%%-----------------------------------------------------------------------------
%%% gen_server interface
%%%-----------------------------------------------------------------------------

%%
%%
%%
init(_) ->
    State0 = read_config_file(),
    process_flag(trap_exit, true),
    {ok, State0}.

%%
%%
%%
%% handle_call(Request, From, State)
handle_call({get_parameter, ParameterName}, _, State) ->
    Reply = case lists:keysearch(util:a2a(ParameterName), 1, State) of
        {value, {_, Value}} ->
	    Value;
	false ->
            {error, {unknow_parameter, ParameterName}}
    end,
    {reply, Reply, State};

handle_call({get_all}, _, State) ->
    {reply, State, State};

handle_call({update}, _, _) ->
    NewState = read_config_file(),
    {reply, ok, NewState};

handle_call(_, _, State) ->
    {reply, unknown_request, State}.

%%
%%
%%
%% handle_cast(Msg, State) ->
handle_cast(_, State) ->
    {noreply, State}.

%%
%%
%%
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
read_config_file() ->    
    {ok, FileName} = config_file_name(),
    case file:read_file(FileName) of
        {ok, BinaryObject} ->	    
            parse_config_file(binary_to_list(BinaryObject));
        {error, Reason} ->
            throw({error, Reason})
    end.

%%
%%
%%
config_file_name() ->
    case init:get_argument(?CONFIG_FLAG) of
	    {ok, L} ->
	        config_file_name(L);
	    _ ->
	        try_file("storage.conf")
    end.

%%
config_file_name([[K,V]|_]) when K == "config_file_name" ->
    {ok, V};
config_file_name([_|T]) ->
    config_file_name(T);
config_file_name([]) ->
    try_file("storage.conf").

try_file(File) ->
    case util:file_size(File) of
        {ok, _Size} ->
            {ok, File};
        _ ->
            throw({error, unknown_config_file})
    end.

%%
%%
%%
parse_config_file(FullLines) ->
    Lines = split_lines(FullLines),
    parse_config_file_lines(Lines, 1).


%%
%%
%%
split_lines(L) -> split_lines(L,[]).

%%
split_lines([$\\,$\\|T], Line) -> split_lines([$\\|T], Line);
split_lines([$\\,$\n|T], Line) -> split_lines(T, Line);
split_lines([$\n|T], Line)     -> [lists:reverse(Line)|split_lines(T,[])];
split_lines([H|T], Line)       -> split_lines(T,[H|Line]);
split_lines([], Line)          -> [lists:reverse(Line)].

%%
%%
%%
parse_config_file_lines([Line | T], LineNo) ->
    case catch parse_config_file_line(Line) of
	{ok, ignore} -> 
	    parse_config_file_lines(T,LineNo+1);
	{ok, ParsedLine} -> 
	    [ParsedLine | parse_config_file_lines(T,LineNo+1)];
	_ -> 
	    throw({error, "Error al parsear el fichero de configuracion. Linea " ++ integer_to_list(LineNo)})
    end;

parse_config_file_lines([], _) ->
    [].

%%
parse_config_file_line(Line) ->
    LineLength = length(Line),
    case regexp:match(Line, "^[ ]*(#.*)?$") of
        {match, 1, LineLength} ->
	    {ok, ignore};
	_ when LineLength == 0 ->
	    {ok, ignore};
	_ ->
	    case regexp:match(Line, "^[ ]*.*[ ]*=[ ]*.*[ ]*$") of
                {match, 1, LineLength} ->
                    parse_name_value_pair(Line);
	        _ ->
		    error
	    end
    end.

%%
parse_name_value_pair(Line) ->
    case regexp:split(Line, "=") of
        {ok, [Name, Value]} ->
            {ok, ValueTokens, _} = erl_scan:string(Value++"."),
            {ok, TermValue} = erl_parse:parse_term(ValueTokens),
            Pair = {util:a2a(util:trim(Name)), TermValue},
	    {ok, Pair};
	_ ->
	    error
    end.
