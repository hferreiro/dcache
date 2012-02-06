-module(launcher).

-export([start/0]).

start() ->
    application:start(storage).
