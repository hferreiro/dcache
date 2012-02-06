-ifndef(_PIPE_HRL).
-define(_PIPE_HRL, true).

-record(pipe_options, { id        = now(),
                        notify    = {storage.util.monitor, notify},  %% {storage.util.monitor, no_notify} / {storage.util.monitor, notify}
                        policy    = normal,                          %% normal / {cbr, Bitrate} / {range, BitrateMin, BitrateMax}
                        trigger   = {inf, none},                     %% {NotifyPos, NotifyFun}: when piped more than NotifyPos bytes, apply NotifyFun()
                        blockSize = 16384,                           %% default blocksize
                        range     = complete                         %% {StartByte, inf} / {StartByte, Length} / 'complete'
                      }).

-define(DEFAULT_PIPE_OPTIONS, #pipe_options{}).

-endif.
