%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : Read file data source (from VoDKA project)
%%%-----------------------------------------------------------------------------

-module(storage.pipe.ds.dummy).

-import(storage.util.util).

-include("ds_info.hrl").

-export([init/2, read/1, done/1, abort/1]).

%%%-----------------------------------------------------------------------------
%%% API
%%%-----------------------------------------------------------------------------

%%
%%
%%
init({Name, Size, BlockSize}, {StartByte, inf}) ->
    NewSize = util:max(0, Size-StartByte),
    {ok, #ds_info{ proplist = [{size, Size}, {name, Name}, {range, {StartByte, inf}}] }, {Name,  NewSize, BlockSize}};

init({Name, Size, BlockSize}, {StartByte, Length}) ->
    NewSize = util:min(util:max(Size-StartByte, 0), Length),
    {ok, #ds_info{ proplist = [{size, Size}, {name, Name}, {range, {StartByte, Length}}] }, {Name,  NewSize, BlockSize}};

init({Name, Size, BlockSize}, complete) ->
    {ok, #ds_info{ proplist = [{size, Size}, {name, Name}, {range, complete}] }, {Name,  Size, BlockSize}}.


%%
%%
%%
read({Name, 0, _}) ->
    {done, Name};
read({Name, Size, BlockSize}) when Size > BlockSize ->
    BSize = 8 * BlockSize,
    {ok, <<0:BSize>>, {Name, Size-BlockSize, BlockSize}};
read({Name, Size, BlockSize}) ->
    BSize = 8 * Size,
    {ok, <<0:BSize>>, {Name, 0, BlockSize}}.

%%
%%
%%
done(_) ->
    ok.

%%
%%
%%
abort(_) ->
    ok.
