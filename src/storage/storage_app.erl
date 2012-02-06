-module(storage.storage_app).
-behaviour(application).

-import(application).
-import(random).
-import(yaws_api).
-import(yaws_config).

-import(storage.storage_sup).
-import(storage.util.config).

-include("yaws.hrl").
-include("config.hrl").

-export([start/2, stop/1]).

start(_Type, _StartArgs) ->
    application:start(crypto),
    ok = seed(),
    case storage_sup:start() of
	    {ok, Pid} ->
            case config:get_parameter(?STORAGE_YAWS) of
                true ->
                    _ = application:start(yaws),
                    GC = (yaws_config:make_default_gconf(true, "id"))#gconf{ logdir = config:get_parameter(?STORAGE_ROOT) ++ "/log" },
                    SC = #sconf{ port              = config:get_argument("yaws_port", ?YAWS_PORT),
                                 servername        = "P2P Storage HTTP server",
                                 partial_post_size = 10000000, %10 Megas
                                 listen            = {0,0,0,0},		
                                 docroot           = config:get_parameter(?YAWS_ROOT_DIR)},
                    yaws_api:setconf(GC, [[SC]]);
                false ->
                    true
            end,
	    {ok, Pid, []};
	Error ->
	    {error, Error}
    end.

stop(_State) ->
    ok.

seed() ->
    {A1, A2, A3} = now(),
    random:seed(A1, A2, A3),
    ok.
