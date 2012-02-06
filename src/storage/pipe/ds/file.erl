%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : Read file data source (from VoDKA project)
%%%-----------------------------------------------------------------------------

-module(storage.pipe.ds.file).

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
    case file:open(Filename, [read, raw, binary]) of
        {ok, IoDevice} ->
            {ok, FileInfo} = file:read_file_info(Filename),
            case Range of
                complete ->
                    {ok,
                      #ds_info{ proplist = [{size, FileInfo#file_info.size},
                                            {name, Filename},
                                            {range, Range}] },
                      {IoDevice, BytesPerChunk, FileInfo#file_info.size, file:read(IoDevice, BytesPerChunk)}};
                {StartByte, inf} ->
                    {ok, _} = file:position(IoDevice, StartByte),
                    Length = util:max(0, FileInfo#file_info.size-StartByte),
                    {ok,
                      #ds_info{ proplist = [{size, FileInfo#file_info.size},
                                            {name, Filename},
                                            {range, Range}] },
                      {IoDevice, BytesPerChunk, Length, file:read(IoDevice, BytesPerChunk)}};
                {StartByte, Length} ->
                    {ok, _} = file:position(IoDevice, StartByte),
                    {ok,
                      #ds_info{ proplist = [{size, FileInfo#file_info.size},
                                            {name, Filename},
                                            {range, Range}] },
                      {IoDevice, BytesPerChunk, Length, file:read(IoDevice, BytesPerChunk)}}
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
    {ok, Data, {IoDevice, BytesPerChunk, Acc-size(Data), file:read(IoDevice, BytesPerChunk)}}.

%%
%%
%%

done({IoDevice, 0}) ->
    file:close(IoDevice);
done({IoDevice, _}) ->
    ok = file:close(IoDevice),
    {error, premature_end}.

%%
%%
%%
abort({IoDevice, _, _, _}) ->
    catch file:close(IoDevice),
    ok.
