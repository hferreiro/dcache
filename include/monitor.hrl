-ifndef(_MONITOR_HRL).
-define(_MONITOR_HRL, true).

-record(event,
	{
          timestamp,
	  process_type,
	  process_id,
	  event_type,
	  data
	 }).

-define(ANY_EVENT, any_event).
-define(ANY_PROCESS, any_process).

-define(OBSERVERS, observers).
-define(DECLARED, declared).

-define(NAME, name).
-define(TYPE, type).

-define(VALID_CLAUSES, [?NAME, ?TYPE]).

-endif.
