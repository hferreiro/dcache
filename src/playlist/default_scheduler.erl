-module(playlist.default_scheduler).

-import(calendar).
-import(io_lib).
-import(lists).

-import(storage.util.monitor).

-include("playlist.hrl").

-export([
	schedule/4
    	]).

schedule({Scheduled, []}, Free, _Download, _Cancel) ->
    monitor:notify(default_scheduler, vdebug, "Scheduling - no items"),
    {{Scheduled, []}, Free};
schedule({[], PlayList}, Free, Download, _Cancel) ->
    monitor:notify(default_scheduler, vdebug, "Scheduling - scheduled empty"),
    {{Done, Remaining}, NewFree} = download(PlayList, Free, Download),
    {{Done, Remaining}, NewFree};
schedule({Scheduled, [Item|_] = PlayList}, Free, Download, Cancel) ->
    monitor:notify(default_scheduler, vdebug, "Scheduling"),
    {_Date, Time} = calendar:now_to_local_time(now()),
    {Size, NewScheduled} = case ?TST(Item) =< Time of
                               true ->
                                   {free(Scheduled, Cancel), []};
                               false ->
                                   [Actual|Old] = sort_by_tst(Scheduled),
                                   {free(Old, Cancel), [Actual]}
                           end,
    {{Done, Remaining}, NewFree} = download(PlayList, Size + Free, Download),
    {{NewScheduled ++ Done, Remaining}, NewFree}.

% helpers

download(List, Free, Download) ->
    do_download([], List, Free, Download).

do_download(Done, [], Free, _Download) ->
    {{Done, []}, Free};
do_download(Done, [Item|Rest] = List, Free, Download) ->
    case ?SIZE(Item) > Free of
        true ->
            {{Done, List}, Free};
        false ->
            monitor:notify(default_scheduler, debug, io_lib:format("Downloading ~p", [?MO(Item)])),
            ok = Download(?MO(Item), ?SERVER(Item)),
            do_download([Item|Done], Rest, Free - ?SIZE(Item), Download)
    end.

free(List, Cancel) ->
    lists:foldl(fun(Item, Size) ->
                    monitor:notify(default_scheduler, debug, io_lib:format("Freeing ~p", [?MO(Item)])),
                    case Cancel(?MO(Item)) of
                        ok ->
                            ?SIZE(Item) + Size;
                        {error, not_found} ->
                            Size
                    end
                end, 0, List).

insert_by_tst(List, Item) ->
    lists:umerge(fun(Item1, Item2) ->
                     ?TST(Item1) >= ?TST(Item2)
                 end, List, [Item]).

sort_by_tst(List) ->
    lists:foldl(fun(Item, Acc) ->
                    insert_by_tst(Acc, Item)
                end, [], List).

