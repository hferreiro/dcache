-module(controller).

-import(file).
-import(http).
-import(inet).
-import(lists).
-import(os).
-import(random).
-import(regexp).
-import(timer).

-import(storage.registry).
-import(storage.util.graphviz).
-import(storage.util.util).

-export([
    graph/0,
    get_playlist/0,
    get_playlist/1,
    server/1,
    add/1,
    add/2,
    del/1,
    arrancar/1,
    parar/1
        ]).

graph() ->
    {A, B, C} = now(),
    random:seed(A, B, C),
    {ok, Data} = registry:snapshot(),
    {ok, Map, Png} = graphviz:circo(Data),
    file:write_file("yaws/images/graph.png", Png),
    {html, "<img src=\"images/graph.png?" ++
        integer_to_list(random:uniform(1000000)) ++ 
        "\" usemap=\"#ring\"></img>" ++ binary_to_list(Map)}.

server(Server) ->
    {ok, {_, _, Html}} = http:request(util:http_url(Server, "")),
    {match, List} = regexp:matches(Html, "(estrela|lambda|gnu|tux)\.png"),
    Files = proccess(List, Html),
    get_size(Server, remove_duplicates(Files)).

defined(List) ->
    Names = lists:filter(fun({Name, _}) ->
                             lists:sublist(Name, length(Name) - 2, 3) == "chk"
                         end, List),
    lists:map(fun({Name, Size}) ->
                  Name2 = lists:sublist(Name, length(Name) - 3),
                  LisI = lists:foldl(fun({N, V}, Acc) ->
                                         case N == Name2 ++ "listid" of
                                             true ->
                                                 case V of
                                                     undefined ->
                                                         Acc;
                                                     _ ->
                                                         V
                                                 end;
                                             false ->
                                                 Acc
                                         end
                                     end, "Lista", List),
                  Time = lists:foldl(fun({N, V}, Acc) ->
                                         case N == Name2 ++ "txt" of
                                             true ->
                                                 case V of
                                                     undefined ->
                                                         Acc;
                                                     _ ->
                                                         V
                                                 end;
                                             false ->
                                                 Acc
                                         end
                                     end, "00:00", List),
                  {LisI, Name2, Size, Time}
              end, Names).

arrancar([{"porto", Porto}]) ->
    {ok, Name} = registry:new(),
    os:cmd("./playlist daemon " ++ Name ++ " " ++ Porto).

parar([{"nodo", Name}]) ->
    {ok, Nodo} = registry:name(Name),
    os:cmd("./playlist stop " ++ Nodo).

add(Args) ->
    L = defined(Args),
    lists:foreach(fun({Lista, Name, _Size, Time}) ->
                      playlist:add(Lista, Name, {localhost, 80}, tst(Time))
                  end, L),
    ok.

add(Name, Args) ->
    {ok, Node} = registry:name(Name),
    {ok, Host} = inet:gethostname(),
    rpc:call(list_to_atom(Node ++ "@" ++ Host), controller, add, [Args]).

del([{"listid", ListId}|_]) ->
    case ListId of
        "" ->
            true;
        _ ->
            playlist:remove_list(ListId)
    end,
    ok.

tst(Time) ->
    {ok, [Hour, Min]} = regexp:split(Time, ":"),
    {list_to_integer(Hour), list_to_integer(Min), 0}.

proccess([], _) ->
    [];
proccess([{Start, Length}|R], Html) ->
    [lists:sublist(Html, Start, Length) | proccess(R, Html)].

get_size(_, []) ->
    [];
get_size(Server, [F|T]) ->
    {ok, Size} = util:file_size({Server, F}),
    [{F, integer_to_list(Size)}|get_size(Server, T)].

get_playlist() ->
    playlist:getlist().

get_playlist(Name) ->
    {ok, Node} = registry:name(Name),
    {ok, Host} = inet:gethostname(),
    rpc:call(list_to_atom(Node ++ "@" ++ Host), playlist, getlist, []).

remove_duplicates(L) ->
    List = lists:foldl(fun(X, Acc) ->
		                   case lists:member(X, Acc) of
		                       true  -> Acc;
		                       false -> [X|Acc]
		                   end
	                   end, [], L),
    lists:reverse(List).
