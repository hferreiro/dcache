-ifndef(_DS_INFO_HRL).
-define(_DS_INFO_HRL, true).

%% Now, ds_info is a property list. PropList is a [{Key,Value}] pair.
%% Some common properties are:
%%     * name         --> name
%%     * size         --> size in bytes
%%     * mimetype     --> mimetype
%%     * range        --> {StartByte, inf} / {StartByte, Length} / 'complete'

-record(ds_info, { proplist = []
                 }).

-define(DS_NAME(Info), storage.util.proplist:get(name, "unknown", Info#ds_info.proplist)).
-define(DS_SIZE(Info), storage.util.proplist:get(size, "unknown", Info#ds_info.proplist)).
-define(DS_MIMETYPE(Info), storage.util.proplist:get(mimetype, "unknown", Info#ds_info.proplist)).
-define(DS_RANGE(Info), storage.util.proplist:get(range, "unknown", Info#ds_info.proplist)).
-define(DS_LENGTH(Info), (fun(__info__) -> 
                              case ?DS_SIZE(__info__) of
                                  "unknown" -> "unknown";
                                  __size__  -> case ?DS_RANGE(__info__) of
                                                   "unknown"             -> "unknown";
                                                   complete              -> __size__;
                                                   {__start_byte__, inf} -> __size__ - __start_byte__;
                                                   {_, __length__}       -> __length__
                                               end
                              end
                          end)(Info)).

-endif.
