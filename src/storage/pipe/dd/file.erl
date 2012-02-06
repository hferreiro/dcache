%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : Write file data destination (from VoDKA project)
%%%-----------------------------------------------------------------------------

-module(storage.pipe.dd.file).

-import(file).
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
    case file:open(Filename, [write, raw, binary]) of
        {ok, IoDevice} ->
            case proplist:get(range, complete, DS_info#ds_info.proplist) of
                {StartByte, _} ->
                    case file:position(IoDevice, StartByte) of
                        {ok, _}         -> {ok, IoDevice};
                        {error, Reason} -> {error, Reason}
                    end;
                complete -> {ok, IoDevice}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%%
%%
%%
write(Data, IoDevice) ->
    case file:write(IoDevice, Data) of
	ok    -> {ok, IoDevice};
	Error -> Error
    end.

%%
%%
%%
done(IoDevice) ->
    file:close(IoDevice).

%%
%%
%%
abort(IoDevice) ->
    catch file:close(IoDevice),
    ok.
