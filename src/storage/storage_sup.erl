-module(storage.storage_sup).
-behaviour(supervisor).

-import(supervisor).

-import(storage.util.util).

-export([start/0, init/1]).

start() ->
	supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = {one_for_all, 50, 60},
    {ok, {SupFlags, [ child(storage.util.config, []),
                      child(storage.util.monitor, []),
                      child(storage.util.file_logger, []),
                      child(storage.pipe.util.sfile, []),
                      child(storage.chord, []),
                      child(storage.dstate, []),
                      child(storage.storage, []) ]}}.

child(Module, Args) ->
    {A,B,C} = erlang:now(),
    { util:a2a(util:a2l(Module) ++ "_" ++ util:a2l(A) ++ util:a2l(B) ++ util:a2l(C)),
      {Module, start_link, Args},
      permanent,
      2000,
      worker,
      [Module] }.
