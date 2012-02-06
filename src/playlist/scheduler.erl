-module(playlist.scheduler).

-import(storage.util.config).

-include("config.hrl").

-export([
    schedule/4
		]).

schedule(PlayList, Free, Download, Cancel) ->
    (config:get_parameter(?PLAYLIST_SCHEDULER)):schedule(PlayList, Free, Download, Cancel).
