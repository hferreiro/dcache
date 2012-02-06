%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : -
%%%-----------------------------------------------------------------------------

-module(storage.pipe.ds.http_get).

-import(file).
-import(gen_tcp).
-import(inet).
-import(lists).
-import(regexp).
-import(string).
-import(storage.util.util).
-import(storage.util.proplist).

-include("ds_info.hrl").

-export([init/2, read/1, done/1, abort/1]).

-define(DEFAULT_TIMEOUT, 10000).
-define(DEFAULT_PORT, 80).

-record(state, { socket,   %% Opened socket
                 timeout,  %% Socket timeout
                 info,     %% HTTP header info
                 length,   %% Expected bytes to receive
                 chunked,  %% Chunked transfer encoding flag (HTTP/1.1 - RFC 2068 - 3.6, 14.40 and 19.4.6)
                 data,     %% Buffered data
                 sum_read  %% Current read bytes
               }).

%%%-----------------------------------------------------------------------------
%%% API
%%%-----------------------------------------------------------------------------

%%
%%
%%
init({Host, Port, File, DS_info}, Range) when record(DS_info, ds_info) ->
    init({Host, Port, File, DS_info, ?DEFAULT_TIMEOUT}, Range);

init({Host, Port, File, DS_info, Tout}, Range) when record(DS_info, ds_info) ->
    case new_socket(Host, Port, Tout) of
        {ok, Socket} ->
            HeadPacket = "HEAD " ++ File ++ " HTTP/1.1\r\n" ++
                         "Host: " ++ util:a2l(Host) ++ ":" ++ util:a2l(Port) ++ "\r\n" ++
                         "Accept: */*\r\n\r\n",
            case gen_tcp:send(Socket, HeadPacket) of
                ok ->
		    case process_header(Socket, Tout) of
			{ok, Size, _, _, _} -> do_init(Socket, 2, Size, Host, Port, File, DS_info, Tout, Range);
                        Error               -> Error
                    end;
                Error -> Error
            end;
	Error -> Error
    end;

init(URL, Range) when list(URL) ->
    case storage.util.url:parse(URL) of
	{http, {_, _, _, _}=Ip, default, File, _} -> init({util:ip2l(Ip), "/" ++ File}, Range);
	{http, {_, _, _, _}=Ip, Port, File, _}    -> init({util:ip2l(Ip), Port, "/" ++ File}, Range);
	{http, Host, default, File, _}            -> init({Host, "/" ++ File}, Range);
	{http, Host, Port, File, _}               -> init({Host, Port, "/" ++ File}, Range);
	Error                                     -> Error
    end;

init({Host, File}, Range) ->
    init({Host, ?DEFAULT_PORT, File}, Range);

init({Host, Port, File}, Range) ->
    init({Host, Port, File, ?DEFAULT_TIMEOUT}, Range);

init({Host, Port, "", Tout}, Range) ->
    init({Host, Port, "/", Tout}, Range);

init({Host, Port, File, Tout}, Range) ->
    init({Host, Port, File, #ds_info{proplist=[{name,"http://" ++ Host ++ ":" ++ integer_to_list(Port) ++ File}]}, Tout}, Range).

%%
do_init(_, 0, _, _, _, _, _, _, _) ->
    {error, get_failled};
do_init(Socket, N, Size, Host, Port, File, DS_info, Tout, Range) ->
    RangeStr = case Range of
                   complete         -> "";
                   {StartByte, inf} -> "Range: bytes=" ++ util:a2l(StartByte) ++ "-" ++ "\r\n";
                   {StartByte, L}   -> "Range: bytes=" ++ util:a2l(StartByte) ++ "-" ++ util:a2l(StartByte+L) ++ "\r\n"
               end,
    GetPacket = "GET " ++ File ++ " HTTP/1.1\r\n" ++
                RangeStr ++
                "Connection: close\r\n" ++
                "User-Agent: MPlayer/1.0\r\n" ++
                "Host: " ++ util:a2l(Host) ++ ":" ++ util:a2l(Port) ++ "\r\n" ++
                "Accept: */*\r\n\r\n",
    case gen_tcp:send(Socket, GetPacket) of
        ok ->
            case process_header(Socket, Tout) of
                {ok, Length, MimeType, Info, Data} ->
                    TransferEncoding = case lookup("Transfer-Encoding", Info) of
                                           {yes, X} -> X;
                                           no       -> undefined
                                       end,
                    case (TransferEncoding=="chunked") or (TransferEncoding==undefined) of
                        true ->
                            State0 = #state{ socket   = Socket,
                                             timeout  = Tout,
                                             info     = Info,
                                             length   = Length,
                                             chunked  = (TransferEncoding=="chunked"),
                                             data     = Data,
                                             sum_read = 0 },
                            {NewMimeType, _}  = proplist:get_sure(mimetype, MimeType, DS_info#ds_info.proplist),
                            NewDS_info1 = DS_info#ds_info{ proplist= proplist:set(mimetype, NewMimeType, DS_info#ds_info.proplist) },
                            NewDS_info2 = DS_info#ds_info{ proplist= proplist:set(size, Size, NewDS_info1#ds_info.proplist) },
                            NewDS_info3 = DS_info#ds_info{ proplist= proplist:set(range, Range, NewDS_info2#ds_info.proplist) },
                            {ok, NewDS_info3, State0};
                        false -> {error, {unknown_transfer_encoding, TransferEncoding}}
                    end;
                {error, closed} ->
                    catch gen_tcp:close(Socket),
                    case new_socket(Host, Port, Tout) of
                        {ok, NewSocket} -> do_init(NewSocket, N-1, Size, Host, Port, File, DS_info, Tout, Range);
                        Error           -> Error
                    end;
                Error -> Error
            end;
        {error, closed} ->
            catch gen_tcp:close(Socket),
            case new_socket(Host, Port, Tout) of
                {ok, NewSocket} -> do_init(NewSocket, N-1, Size, Host, Port, File, DS_info, Tout, Range);
                Error           -> Error
            end;
        Error -> Error
    end.

%%
%%
%%
read(State) ->
    case gen_tcp:recv(State#state.socket, 0, State#state.timeout) of 
	{ok, Packet}    -> process_body(State, Packet);
	{error, Reason} ->
	    case Reason of
		closed -> {done, State};
		Reason -> {error, Reason}
	    end
    end.

%%
%%
%%
done(State) ->
    abort(State),
    case State#state.sum_read == State#state.length of
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
new_socket(Host, Port, Tout) ->
    gen_tcp:connect(Host, Port, [binary, {packet,raw}, {active,false}], Tout).

%%
%%
%%
process_header(Socket, Tout) ->
    process_header(Socket, Tout, []).

%%
%%
%%
process_header(Socket, Tout, OldHeader) ->
    case gen_tcp:recv(Socket, 0, Tout) of
	{ok, Data} ->
	    case is_header_received(OldHeader, Data) of
		{true, Header, RestData} ->
                    case parse_reply(Header) of
		        {ok, {_, Code, Info, []}} -> 
                            case (Code == 200) or (Code == 206) of
				true ->
				    Length = case lookup("Content-Length", Info) of
                                                 {yes, X} -> list_to_integer(X);
                                                 no       -> "unknown"
                                             end,
				    MimeType = case lookup("Content-Type",Info) of
                                                   {yes, T} -> T;
                                                   no       -> "application/octet-stream"
                                               end,
				    {ok, Length, MimeType, Info, RestData};
			         false -> {error, {?MODULE, not_found}}
			    end;
			Error -> {error, Error}
		    end;
		{false, Header, _} -> process_header(Socket, Tout, Header)
	    end;
	Error -> Error
    end.

%%
is_header_received(OldHeader, Data) ->
    {Flag, Header, Rest} = is_header_received_aux(binary_to_list(Data), []),
    {Flag, lists:append(OldHeader, Header), list_to_binary(Rest)}.

is_header_received_aux([$\r, $\n, $\r, $\n | Rest], Acc) ->
    {true, lists:reverse(Acc), Rest};
is_header_received_aux([X|Rest], Acc) ->
    is_header_received_aux(Rest, [X|Acc]);
is_header_received_aux([], Acc) ->
    {false, lists:reverse(Acc), []}.

%%
lookup(_,[]) ->
    no;
lookup(X,[{X,Y}|_]) ->
    {yes, Y};
lookup(X,[_|Y]) ->
    lookup(X,Y).

%%
%%
%%
process_body(#state{chunked=false}=State, Packet) ->
    Data = concat_binary([State#state.data, Packet]),
    NewState = State#state{ data = <<>>,
                            sum_read = State#state.sum_read + size(Data) },
    {ok, Data, NewState};

process_body(#state{chunked=true}, _) ->
    {error, http_1_1_chunked_body_not_implemented}.

%%%----------------------------------------------------------------------
%%% HTTP 1.0, HTTP 1.1, etc.
%%%----------------------------------------------------------------------

%%
%%
%%
parse_reply(Reply) ->
  case get_header_line(Reply, []) of
      {ok, R1, Protocol, Code} ->
          case get_info_lines(R1, [], []) of
	      {ok, R2, Info} ->
	          case get_body(R2) of
                      {ok, Body} -> {ok, {Protocol, Code, Info, Body}};
		      Error      -> Error
		  end;
	      Error -> Error
	  end;
      Error -> Error
  end.

%%
get_header_line([$\r,$\n|T], Acc) ->
    get_header_line_end(T, lists:reverse(Acc));
get_header_line([H|T], Acc) ->
    get_header_line(T, [H|Acc]);
get_header_line([], Acc) ->
    get_header_line_end([], lists:reverse(Acc)).

%%
get_header_line_end(R, HLine) ->
    case regexp:split(HLine, " ") of
        {ok, [Protocol,CodeStr|_]} ->
	    case catch list_to_integer(CodeStr) of
	        {'EXIT', _} -> {error, parse_error};
		Code        -> {ok, R, Protocol, Code}
	    end;
	_ -> {error, parse_error}
    end.

%%
get_info_lines([$\r,$\n|T], Acc, Info) ->
    get_info_line_end(T, lists:reverse(Acc), Info);
get_info_lines([H|T], Acc, Info) ->
    get_info_lines(T, [H|Acc], Info);
get_info_lines([], Acc, Info) ->
    get_info_line_end([], lists:reverse(Acc), Info).

%%
get_info_line_end(R, [], Info) ->
    {ok, R, Info};
get_info_line_end(R, ILine, Info) ->
    case get_info(ILine) of
      {ok, V} -> get_info_lines(R, [], [V|Info]);
      Error   -> Error
    end.

%%
get_info(ILine) ->
    case string:chr(ILine, $:) of
        0  -> {error, parse_error};
        Ix ->
            V = {util:trim(string:substr(ILine, 1, Ix-1)),
                 util:trim(string:substr(ILine, Ix+1))},
	    {ok, V}
    end.

%%
get_body(L) ->
    {ok, L}.
