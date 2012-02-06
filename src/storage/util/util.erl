%%%-----------------------------------------------------------------------------
%%% Author  : Carlos Abalde <cabalde@udc.es>
%%% Purpose : -
%%%-----------------------------------------------------------------------------

-module(storage.util.util).

-import(lists).
-import(gen_server).
-import(erlang).
-import(erl_parse).
-import(erl_scan).
-import(file).
-import(http).
-import(io).
-import(io_lib).
-import(random).
-import(math).
-import(regexp).
-import(rpc).
-import(inet_udp).
-import(prim_inet).

-import(storage.util.util).

-include_lib("kernel/include/file.hrl").

-include("config.hrl").

-export([start_link_gen_server/4]).
-export([call/2, cast/2, reentrant_call/2]).
-export([log/2, add/3, sub/3, seq/3, in_seq/4, foldl_seq/5]).
-export([keysearch_and_delete/3, random_nth/1, shake/1]).
-export([trim/1, a2l/1, a2a/1, a2b/1, a2i/1, a2f/1, min/2, max/2]).
-export([timestamp/0, to_miliseconds/1, elapsed_miliseconds/1, elapsed_seconds/1, tag/1]).
-export([term_to_string/1, string_to_term/1, mktemp/0, mkdir/1, mktemp_name/1]).
-export([node/1, host2l/1, ip2l/1, http_url/2, file_size/1]).

%%%-----------------------------------------------------------------------------
%%% gen_server
%%%-----------------------------------------------------------------------------

-define(GEN_SERVER_CHANCES, 32).

%%
%% => Accesos de escritura al estado que esperar respuesta: call/1
%%        - bloquean al cliente (call)      	
%%        - no reentrantes (funcionamiento natural gen_sever) (un solo escritor simultaneo)
%%	  - por lo tanto, posible interbloqueo => necesarios timeouts bajos y logica para reintentos
%% => Accesos de escritura al estado sin esperar respuesta: cast/1
%%	  - no bloquean al cliente (cast)
%%        - no reentrantes (funcionamiento natural gen_sever) (un solo escritor simultaneo)
%% => Accesos de lectura al estado: reentrant_call/1
%%        - bloquean al cliente (call) (obviamente este espera un resultado)
%%        - reentrantes (creacion de subproceso cliente en espera) (posible mas de un lector simultaneo)
%%

%%
%%
%%
call(ServerRef, Request) ->
%    do_call(ServerRef, Request, ?GEN_SERVER_CHANCES, 20000).
    gen_server:call(ServerRef, Request, ?GENSERVER_TIMEOUT).

%do_call(_, _, 0, _) ->
%    {error, timeout};
%do_call(ServerRef, Request, Chances, Timeout) ->
%   case catch gen_server:call(ServerRef, Request, Timeout) of
%	{'EXIT', _} ->
%case Chances < ?GEN_SERVER_CHANCES of
%    true -> io:format("~p ---> ~p~n", [Chances, {ServerRef, Request}]);
%    false -> lala
%end,
%            receive after (100 * (?GEN_SERVER_CHANCES - Chances)) -> true end,
%	    do_call(ServerRef, Request, Chances-1, Timeout);
%	_Result -> _Result
%    end.

%%
%%
%%
reentrant_call(ServerRef, Request) ->
    case util:call(ServerRef, {reentrant, Request}) of
        {ok, Pid, Ref} ->
            receive
                {Pid, Ref, Result}    -> Result;
                {'EXIT', Pid, Reason} -> {error, Reason}  %% El proceso llamador podria haber habilitado el trap_exit
                                                          %% de modo que la muerte del worker que se linkara a el
                                                          %% no lo sacaria de la espera
            end;
        _Else -> _Else
    end.

%%
%%
%%
cast(ServerRef, Request) ->
    spawn(fun() -> util:call(ServerRef, Request) end),
    ok.

%%
%%
%%
start_link_gen_server({_, ServerName}=SN, Module, Args, Options) ->
    case gen_server:start_link(SN, Module, Args, Options) of
        {ok, Pid} ->
	    catch unregister(ServerName),
	    register(ServerName, Pid),
	    {ok, Pid};
        _Else ->
            _Else
    end.

%%%-----------------------------------------------------------------------------
%%% math
%%%-----------------------------------------------------------------------------

%%
%%
%%
log(B, X) ->
    math:log10(X)/math:log10(B).

%%
%%
%%
min(A, B) when A < B -> A;
min(_, B) -> B.

%%
%%
%%
max(A, B) when A > B -> A;
max(_, B) -> B.

%%%-----------------------------------------------------------------------------
%%% modular arithmetic
%%%-----------------------------------------------------------------------------

%%
%%
%%
add(A, B, Mod) ->
    case A + B of
        X when X >= 0 -> X rem Mod;
        X             -> ((X rem Mod) + Mod) rem Mod
    end.

%%
%%
%%
sub(A, B, Mod) ->
    add(A, -B, Mod).

%%
%%
%%
seq(A, B, Mod) when B >= A, B < Mod ->
    lists:seq(A, B);
seq(A, B, Mod) when B < A, A < Mod ->
    lists:seq(A, Mod-1) ++ lists:seq(0, B).

%%
%%
%%
in_seq(X, A, B, Mod) when B >= A, B < Mod ->
    (X >= A) and (X =< B);
in_seq(X, A, B, Mod) when B < A, A < Mod ->
    ((X >= A) and (X =< (Mod-1))) or ((X >= 0) and (X =< B)).

%%
%%
%%
foldl_seq(F, AccIn, N, N, _) ->
    F(N, AccIn);
foldl_seq(F, AccIn, A, B, Mod) ->
    foldl_seq(F, F(A, AccIn), add(A, 1, Mod), B, Mod).

%%%-----------------------------------------------------------------------------
%%% Conversiones
%%%-----------------------------------------------------------------------------

%%
%%
%%
a2l(X) when list(X)    -> X;
a2l(X) when atom(X)    -> atom_to_list(X);
a2l(X) when integer(X) -> integer_to_list(X);
a2l(X) when float(X)   -> float_to_list(X);
a2l(X) when tuple(X)   -> tuple_to_list(X).    

%%
%%
%%
a2a(X) when atom(X)    -> X;
a2a(X) when list(X)    -> list_to_atom(X).

%%
%%
%%
a2b(X) when X == "0"     -> false;
a2b(X) when X == "1"     -> true;
a2b(X) when list(X)      -> list_to_atom(X);
a2b(X) when atom(X)      -> X.

%%
%%
%%
a2i(X) when integer(X) -> X;
a2i(X) when list(X)    -> list_to_integer(X).

%%
%%
%%
a2f(X) when float(X) -> X;
a2f(X) when list(X) ->
    case catch list_to_float(X) of
	{'EXIT', _} ->
	    list_to_float(X ++ ".0");
	_Else ->
	    _Else
    end.

%%
%%
%%
string_to_term(StrTerm) ->
    {ok, ItemTokens, _} = erl_scan:string(StrTerm ++ "."),
    erl_parse:parse_term(ItemTokens).

%%
%%
%%
term_to_string(Term) ->
    {ok, lists:flatten(io_lib:format("~w", [Term]))}.  % TODO !!!!!

%%%-----------------------------------------------------------------------------
%%% Lists
%%%-----------------------------------------------------------------------------

%%
%%
%%
keysearch_and_delete(Key, N, TupleList) ->
    case lists:keysearch(Key, N, TupleList) of
        {value, Tuple} -> {value, Tuple, lists:keydelete(Key, N, TupleList)};
        _              -> false
    end.

%%
%%
%%
random_nth(L) ->
    lists:nth(random:uniform(length(L)), L).

%%
%%
%%
shake(L) ->
    shake(L, []).

shake([], Acc) ->
    Acc;
shake(L, Acc) ->
    V = random_nth(L),
    shake(lists:delete(V, L), [V | Acc]).

%%%-----------------------------------------------------------------------------
%%% Misc
%%%-----------------------------------------------------------------------------

%%
%%
%%
trim(List) when list(List) ->
    List1 = skip_spaces(List),
    List2 = skip_spaces(lists:reverse(List1)),
    lists:reverse(List2).

%%
skip_spaces([H|T]) when H == $  ->
    skip_spaces(T);

skip_spaces(List) ->
    List.

%%
%%
%%
timestamp() ->
    {S1, S2, S3} = erlang:now(),
    S1*1000000000000 + S2*1000000 + S3.

%%
%%
%%
to_miliseconds({S1, S2, S3}) ->
    S1*1000000000000 + S2*1000000 + S3.

%%
%%
%%
elapsed_miliseconds({S1, S2, S3}) ->
    elapsed_miliseconds(S1*1000000000000 + S2*1000000 + S3);

elapsed_miliseconds(MicroSecs) ->
    {S1, S2, S3} = erlang:now(),
    round(((S1*1000000000000 + S2*1000000 + S3) - MicroSecs) / 1000).

%%
%%
%%
elapsed_seconds({S1, S2, S3}) ->
    elapsed_seconds(S1*1000000000000 + S2*1000000 + S3);

elapsed_seconds(MicroSecs) ->
    {S1, S2, S3} = erlang:now(),
    round(((S1*1000000000000 + S2*1000000 + S3) - MicroSecs)/1000000).

%%
%%
%%
tag(X) ->
    {S1, S2, S3} = erlang:now(),
    a2a(a2l(X) ++ "_" ++ a2l(S1) ++ a2l(S2) ++ a2l(S3)).

%%
%%
%%
mktemp_name(Prefix) ->
    {A, B, C} = now(),
    {ok, "/tmp/" ++ Prefix ++ integer_to_list(A) ++ integer_to_list(B) ++ integer_to_list(C)}.

%%
%%
%%
mktemp() ->
    {ok, TmpFile} = mktemp_name(""),
    {ok, TmpIoDevice} = file:open(TmpFile, [write, read, raw]),
    {ok, TmpFile, TmpIoDevice}.

%%
%%
%%
mkdir(DirName) ->
    {ok, ["" | Dirs]} = regexp:split(DirName, "/"),
    lists:foldl(fun(Dir, AccIn) ->
                    AccOut = AccIn ++ Dir ++ "/",
                    catch file:make_dir(AccOut),
                    AccOut
                end, "/", Dirs),
    ok.

%%%-----------------------------------------------------------------------------
%%% inet
%%%-----------------------------------------------------------------------------

%%
%%
%%
node(ip) ->
    do_node_addr(addr);
node(broadcast) ->
    do_node_addr(broadaddr);
node(netmask) ->
    do_node_addr(netmask).

%%
do_node_addr(Tag) ->
    case inet_udp:open(0, []) of
        {ok, S} ->
            case prim_inet:ifget(S, "eth0", [Tag]) of
                {ok, [{Tag, Addr}]} -> catch inet_udp:close(S), Addr;
                _                   -> catch inet_udp:close(S), exit({error, unknown_addr})
            end;
        _ -> exit({error, unknown_addr})
    end.

%%
%%
%%
host2l({A, B, C, D}) ->
    ip2l({A, B, C, D});
host2l(Else) ->
    a2l(Else).

%%
%%
%%
ip2l({A, B, C, D}) ->
    a2l(A) ++ "." ++ a2l(B) ++ "." ++ a2l(C) ++ "." ++ a2l(D).

http_url({Host, Port} = _Server, File) ->
    "http://" ++ host2l(Host) ++ ":" ++ a2l(Port) ++ "/" ++ a2l(File).

file_size({Server, File}) ->
    Url = http_url(Server, File),
    case http:request(head, {Url, []}, [], []) of
        {ok, {_Status, Headers, _Body}} ->
            {value, {"content-length", Size}} = lists:keysearch("content-length", 1, Headers),
            {ok, list_to_integer(Size)};
        {error, Reason} ->
            {error, Reason}
    end;
file_size(File) ->
    case file:read_file_info(File) of
        {ok, FileInfo} ->
            {ok, FileInfo#file_info.size};   
        {error, Reason} ->
            {error, Reason}
    end.
