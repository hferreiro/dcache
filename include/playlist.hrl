-ifndef(_PLAYLIST_HRL).
-define(_PLAYLIST_HRL, true).

-record(item, { listid,
                mo,
                server,
                size,
                tst
               }).

-define(LISTID(Item), Item#item.listid).
-define(MO(Item), Item#item.mo).
-define(SERVER(Item), Item#item.server).
-define(SIZE(Item), Item#item.size).
-define(TST(Item), Item#item.tst).

-endif.
