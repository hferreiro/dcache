-ifndef(_CONFIG_HRL).
-define(_CONFIG_HRL, true).

-define(GENSERVER_TIMEOUT, 60000).
-define(CONFIG_FLAG, storage_conf).

-define(REGISTRY, "registry").

%%
%% General
%%
-define(STORAGE_ROOT, "storage.root").
-define(STORAGE_SIZE, "storage.size").
-define(STORAGE_RPC, "storage.rpc").

-define(STORAGE_YAWS, "storage.yaws").
-define(STORAGE_GS, "storage.gs").

%%
%% Playlist
%%
-define(PLAYLIST_SCHEDULER, "playlist.scheduler").
-define(PLAYLIST_SCHEDULER_INTERVAL, "playlist.scheduler.interval").

%%
%% Ring
%%
-define(RING_NEIGHBOR_LOOKUP, "storage.ring.neighbor_lookup").
-define(RING_NEIGHBOR_LOOKUP_TIMEOUT, "storage.ring.neighbor_lookup_timeout").
-define(RING_ID, "storage.ring.id").
-define(RING_MCAST_IP, "storage.ring.mcast.ip").
-define(RING_MCAST_PORT, "storage.ring.mcast.port").
-define(RING_BCAST_PORT, "storage.ring.bcast.port").
-define(RING_PORT, "storage.ring.port").
-define(RING_ANNOUNCE_TIMEOUT, "storage.ring.announce_timeout").

%%
%% Transfer
%%
-define(TRANSFER_MOD, "storage.transfer.mod").
-define(TRANSFER_ARGS, "storage.transfer.args").
-define(TRANSFER_LAN_BLOCK, "storage.transfer.lan.block").
-define(TRANSFER_LAN_POLICY, "storage.transfer.lan.policy").
-define(TRANSFER_SERVER_BLOCK, "storage.transfer.server.block").
-define(TRANSFER_SERVER_POLICY, "storage.transfer.server.policy").

%%
%% Chord
%%
-define(CHORD_M, "storage.chord.m").
-define(CHORD_SUCCESSOR_LIST_SIZE, "storage.chord.successor_list_size").
-define(CHORD_SUCCESSORS_STABILIZATION, "storage.chord.successors_stabilization").
-define(CHORD_FINGERS_STABILIZATION, "storage.chord.fingers_stabilization").
-define(CHORD_SNAPSHOT_FINGERS, "storage.chord.snapshot.fingers").

%%
%% ERPC
%%
-define(ERPC_PORT, "storage.erpc.port").
-define(ERPC_SECRET, "storage.erpc.secret").
-define(ERPC_KEEPALIVE_TIMEOUT, "storage.erpc.keepalive_timeout").

%%
%% Yaws
%%
-define(YAWS_ROOT_DIR, "storage.yaws.root_dir").
-define(YAWS_PORT, "storage.yaws.port").

%%
%% Monitor
%%
-define(MONITOR_NOTIFY, "storage.monitor.notify").

%%
%% Log
%%
-define(FILELOG_EVENTTYPES, "storage.file_log.event_types").

-endif.
