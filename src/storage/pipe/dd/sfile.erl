%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : -
%%%-----------------------------------------------------------------------------

-module(storage.pipe.dd.sfile).

-import(file).
-import(lists).
-import(storage.util.proplist).

-include("ds_info.hrl").

-export([init/2, write/2, done/1, abort/1]).

%%%-----------------------------------------------------------------------------
%%% API
%%%-----------------------------------------------------------------------------

%%
%%
%%
init(DS_info, Filename) ->
    case lists:keysearch(size, 1, DS_info#ds_info.proplist) of
        {value, {_, Size}} -> 
            case file:write_file(Filename ++ ".sfile", term_to_binary(Size)) of
                ok ->
                    case storage.pipe.util.sfile:open(Filename, {write, Size}) of
                        {ok, IoDevice} ->
                            case proplist:get(range, complete, DS_info#ds_info.proplist) of
                                {StartByte, _} ->
                                    case storage.pipe.util.sfile:position(IoDevice, StartByte) of
                                        {ok, _}         -> {ok, IoDevice};
                                        {error, Reason} -> {error, Reason}
                                    end;
                                complete -> {ok, IoDevice}
                            end;
                        {error, Reason} ->
                            {error, Reason}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        false -> {error, unkown_size}
    end.

%%
%%
%%
write(Data, IoDevice) ->
    case storage.pipe.util.sfile:write(IoDevice, Data) of
	ok    -> {ok, IoDevice};
	Error -> Error
    end.

%%
%%
%%
done(IoDevice) ->
    storage.pipe.util.sfile:close(IoDevice).

%%
%%
%%
abort(IoDevice) ->
    catch storage.pipe.util.sfile:close(IoDevice),
    ok.
