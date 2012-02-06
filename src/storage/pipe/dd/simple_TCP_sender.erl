%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : Destination behaviour that sends data through a TCP socket (from VoDKA project)
%%%-----------------------------------------------------------------------------

-module(storage.pipe.dd.simple_TCP_sender).

-import(gen_tcp).

-include("ds_info.hrl").

-export([init/2, write/2, done/1, abort/1]).

%%%-----------------------------------------------------------------------------
%%% API
%%%-----------------------------------------------------------------------------

%%
%%
%%
init(DS_info, {open_for_me_please, Host, Port}) ->
    {ok,Socket} = gen_tcp:connect(Host, Port, [binary, {packet, 0},{active, false}]),
    init(DS_info, {openSocket,Socket});

%%
init(DS_info, {openSocket, Socket}) ->
    send_header(DS_info, Socket),
    {ok,{openSocket,Socket}}.

%%
%%
%%
write(Data, {openSocket, Socket} = State) ->
    case gen_tcp:send(Socket, Data) of
	{error, Reason} -> {error, Reason};
	_               -> {ok,State}
    end.

%%
%%
%%
done(State) ->
    abort(State).

%%
%%
%%
abort({openSocket, Socket}) ->
    catch gen_tcp:close(Socket),
    ok.

%%%-----------------------------------------------------------------------------
%%% Internal implementation
%%%-----------------------------------------------------------------------------

%%
%%
%%
send_header(DS_info, Socket) ->
    BinInfo=term_to_binary(DS_info),
    %% Send length in 4 bytes (@TODO@ check endianness)
    gen_tcp:send(Socket, << (size(BinInfo)):32 >> ),
    gen_tcp:send(Socket,BinInfo).
