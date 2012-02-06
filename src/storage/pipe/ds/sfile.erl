%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : -
%%%-----------------------------------------------------------------------------

-module(storage.pipe.ds.sfile).

-import(file).
-import(storage.util.util).

-include("ds_info.hrl").
-include_lib("kernel/include/file.hrl").

-export([init/2, read/1, done/1, abort/1]).

%%%-----------------------------------------------------------------------------
%%% API
%%%-----------------------------------------------------------------------------

%%
%%
%%
init({Filename, BytesPerChunk}, Range) ->
    case file:read_file(Filename ++ ".sfile") of
        {ok, Binary} ->
            Size = binary_to_term(Binary),
            case storage.pipe.util.sfile:open(Filename, {read, Size}) of
                {ok, IoDevice} ->
                    case Range of
                        complete ->
                            {ok,
                              #ds_info{ proplist = [{size, Size},
                                                    {name, Filename},
                                                    {range, Range}] },
                              {IoDevice, BytesPerChunk, Size, {ok, <<>>}}};
                        {StartByte, inf} ->
                            {ok, _} = storage.pipe.util.sfile:position(IoDevice, StartByte),
                            Length = util:max(0, Size-StartByte),
                            {ok,
                              #ds_info{ proplist = [{size, Size},
                                                    {name, Filename},
                                                    {range, Range}] },
                              {IoDevice, BytesPerChunk, Length, {ok, <<>>}}};
                        {StartByte, Length} ->
                            {ok, _} = storage.pipe.util.sfile:position(IoDevice, StartByte),
                            {ok,
                              #ds_info{ proplist = [{size, Size},
                                                    {name, Filename},
                                                    {range, Range}] },
                              {IoDevice, BytesPerChunk, Length, {ok, <<>>}}}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%%
%%
%%
read({IoDevice, _, Acc, eof}) ->
    {done, {IoDevice, Acc}};
read({_, _, _, {error, Reason}}) ->
    {error, Reason};
read({IoDevice, BytesPerChunk, Acc, {ok, Data}}) ->
    {ok, Data, {IoDevice, BytesPerChunk, Acc-size(Data), storage.pipe.util.sfile:read(IoDevice, BytesPerChunk)}}.

%%
%%
%%
done({IoDevice, 0}) ->
    storage.pipe.util.sfile:close(IoDevice);
done({IoDevice, _}) ->
    ok = storage.pipe.util.sfile:close(IoDevice),
    {error, premature_end}.

%%
%%
%%
abort({IoDevice, _, _, _}) ->
    catch storage.pipe.util.sfile:close(IoDevice),
    ok.
