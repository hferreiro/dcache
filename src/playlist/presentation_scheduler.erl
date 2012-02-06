-module(playlist.presentation_scheduler).

-import(calendar).
-import(io_lib).
-import(lists).

-import(storage.util.monitor).

-include("playlist.hrl").

-define(HOUR_DIFF, 0).
-define(MIN_DIFF, 2).
-define(SEC_DIFF, 0).

-export([
	schedule/4
    	]).

schedule({Scheduled, []}, Free, _Download, _Cancel) ->
    monitor:notify(default_scheduler, vdebug, "Scheduling - no items"),
    monitor:notify(default_scheduler, vdebug, io_lib:format("Scheduled ~p", [Scheduled])),
    {{Scheduled, []}, Free};
schedule({Scheduled, [Item|Rest] = PlayList}, Free, Download, _Cancel) ->
    monitor:notify(default_scheduler, vdebug, "Scheduling"),
    case ready(Item) of
        true ->
            case download(Item, Free, Download) of
                {ok, NewFree} ->
                    monitor:notify(default_scheduler, vdebug, io_lib:format("Scheduled ~p, Playlist ~p", [[Item|Scheduled], Rest])),
                    {{[Item|Scheduled], Rest}, NewFree};
                {error, storage_full} ->
                    {{Scheduled, PlayList}, Free}
            end;
        false ->
            {{Scheduled, PlayList}, Free}
    end.

% helpers

ready(Item) ->
    {_Date, Time} = calendar:now_to_local_time(now()),
    diff(?TST(Item)) =< Time.

diff({H, M, S}) ->
    {H - ?HOUR_DIFF, M - ?MIN_DIFF, S - ?SEC_DIFF}.

download(Item, Free, Download) ->
    case ?SIZE(Item) > Free of
        true ->
            {error, storage_full};
        false ->
            monitor:notify(default_scheduler, debug, io_lib:format("Downloading ~p", [?MO(Item)])),
            ok = Download(?MO(Item), ?SERVER(Item)),
            {ok, Free - ?SIZE(Item)}
    end.

