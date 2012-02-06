%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : - (from VoDKA project)
%%%-----------------------------------------------------------------------------

-module(storage.pipe.transfer.tcp).

-import(gen_tcp).
-import(inet).
-import(net_adm).

-export([init/1, done/1]).

%%%-----------------------------------------------------------------------------
%%% API
%%%-----------------------------------------------------------------------------

%%
%%
%%
init(_Args) ->
    {ok,LSock} = gen_tcp:listen(0, [binary, {packet,0}, {active,false}]),
    {ok, Port} = inet:port(LSock),
    Hostname = net_adm:localhost(),
    { LSock, 
      {storage.pipe.ds.simple_TCP_receiver, {listenSocket, LSock}}, 
      {storage.pipe.dd.simple_TCP_sender, {open_for_me_please, Hostname, Port}} }.

%%
%%
%%
done(LSock) ->
    catch gen_tcp:close(LSock).
