%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : Data source behaviour which receives data from a TCP socket (from VoDKA project)
%%%-----------------------------------------------------------------------------

-module(storage.pipe.ds.simple_TCP_receiver).

-import(gen_tcp).
-import(inet).
-import(lists).
-import(storage.util.util).
-import(storage.util.proplist).

-define(DEFAULT_TIMEOUT, 10000).

-include("ds_info.hrl").

-export([init/2,read/1,done/1,abort/1]).

-record(state, { socket,     % Opened socket
	         length,     % Expected bytes to receive
                 sumread = 0 % Currently read bytes
	       }).

%%%-----------------------------------------------------------------------------
%%% API
%%%-----------------------------------------------------------------------------

%%
%%
%%
init({openSocket, Socket}, complete) ->
    %% Socket is already open
    case catch parse_ds_info(Socket) of
	{ok, DS_info} -> 
	    case lists:keysearch(size, 1, DS_info#ds_info.proplist) of
		{value, {_, Size}} ->
                    Length = case proplist:get(range, complete, DS_info#ds_info.proplist) of
                                 {StartByte, inf} -> util:max(0, Size-StartByte);
                                 {_, TheLength}   -> TheLength;
                                 complete         -> Size
                             end,
                    inet:setopts(Socket,[{recbuf, 65536}]),
		    {ok, DS_info, #state{ socket = Socket,
                                          length = Length }};
		false ->
                    catch gen_tcp:close(Socket),
		    {error, unkown_length}
            end;
	_ ->
            catch gen_tcp:close(Socket),
	    {error, unkown_DS_info}
    end;

%%
init({listenSocket, Socket}, complete) ->
    %% Socket is in Listen state
    case gen_tcp:accept(Socket, ?DEFAULT_TIMEOUT) of
	{ok, OpenSocket} -> 
	    init({openSocket, OpenSocket}, complete);
	{error, Reason} -> 
            catch gen_tcp:close(Socket),
	    {error, Reason}
    end;

%%
init({open_for_me_please, TCPPort}, complete) ->
    case gen_tcp:listen(TCPPort, [binary, {packet,0}, {active,false}]) of
	{error, Reason}    -> {error, Reason};
	{ok, ListenSocket} -> init({listenSocket, ListenSocket}, complete)
    end.
		    

%%
%%
%%
read(State) ->
    case gen_tcp:recv(State#state.socket, 0) of 
	{ok, Packet}    ->  {ok, Packet, State#state{sumread=State#state.sumread+size(Packet)}};
	{error, Reason} ->
	    case Reason of
	        % Hack ahead. We've no way to tell whether the 
		% TCP transmission has finished OK or not
		closed -> {done, State};
		Reason -> {error, Reason}
	    end
    end.

%%
%%
%%
done(State) ->
    abort(State),
    case State#state.sumread == State#state.length of
         true  -> ok;
	 false -> {error, premature_end}
    end.

%%
%%
%%
abort(State) ->
    catch gen_tcp:close(State#state.socket),
    ok.

%%%-----------------------------------------------------------------------------
%%% Internal implementation
%%%-----------------------------------------------------------------------------

%%
%%
%%
parse_ds_info(Socket) ->
    {ok, BinLen} = gen_tcp:recv(Socket, 4), % ds_info length in 32 bits
    {ok, Info} = gen_tcp:recv(Socket, lists:foldl(fun (Ac,X) ->
	         				      X*256 + Ac
	         			          end, 0, binary_to_list(BinLen))),
    {ok, binary_to_term(Info)}.
