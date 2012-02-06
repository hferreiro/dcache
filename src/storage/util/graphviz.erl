-module(storage.util.graphviz).

-import(file).
-import(lists).
-import(os).

-import(storage.chord).
-import(storage.util.util).

-include("config.hrl").

-export([circo/1]).

circo(Data) ->
    {ok, Graph} = dot(Data),
    {ok, SourceFile, SourceIoDevice} = util:mktemp(),
    {ok, PngFile} = util:mktemp_name("graph"),
    {ok, MapFile} = util:mktemp_name("map"),
    file:write(SourceIoDevice, Graph),
    file:close(SourceIoDevice),
    os:cmd("circo -Tcmapx -o " ++ MapFile ++ " -Tpng -o " ++ PngFile ++ " " ++ SourceFile),
    file:delete(SourceFile),
    {ok, Png} = file:read_file(PngFile),
    {ok, Map} = file:read_file(MapFile),
    file:delete(PngFile),
    file:delete(MapFile),
    {ok, Map, Png}.

dot(Data) ->
    Graph = lists:foldl(fun({Node, Succ, Fingers}, Acc) ->
                            This = node(),
                            Links = case Node of
                                        This ->
                                            lists:foldl(fun(Finger, Acc2) ->
                                                            Acc2 ++ name(Node) ++ " -> " ++ name(Finger) ++
                                                                "[style=dashed];\n"
                                                        end, "", Fingers);
                                        _ ->
                                            ""
                                    end,
                            Acc ++ Links ++ "\n" ++ name(Node) ++ " -> " ++ name(Succ) ++ ";\n"
                        end, "", Data),
    Props = lists:foldl(fun({Node, _Succ, Fingers}, Acc) ->
                            Acc ++ name(Node) ++ " [ style=filled fillcolor=" ++ color(Node) ++
                                " tooltip=\"Nodo " ++ name(Node) ++ "\" " ++ root(Node) ++   
                                 " URL=\"" ++ url(Node) ++ "\" label=" ++ label(Node, Fingers) ++ "];\n"
                        end, "", Data),
    {ok, "digraph ring {\n [ bgcolor=\"transparent\" mindist=1.5 ]\n" ++ Props ++ Graph ++ "}"}.

color(Node) ->
    case node() of
	    Node ->
            "\"#9bed6f\"";
        _ ->
            "\"#d5cece\""
    end.

root(Node) ->
    case node() of
        Node ->
            "root=\"true\"";
        _ ->
            ""
    end.   

name(Node) ->
    integer_to_list(chord:chash(Node)).

url(Node) ->
    "admin.yaws" ++ "?node=" ++ name(Node).

label(N, L) ->
    "<<font color=\"black\"><table border=\"0\"><tr>" ++
        "<td bgcolor=" ++ headerColor(N) ++ " colspan=\"2\">Fingers de " ++ name(N) ++ "</td></tr>" ++
            "<tr><td bgcolor=" ++ headerColor(N) ++ ">start</td><td bgcolor=" ++ headerColor(N) ++ ">succ</td></tr>" ++ do_label(L, 1) ++
                "</table></font>>".

headerColor(Node) ->
    case node() of
        Node ->
            "\"#de6d30\"";
        _ ->
            "\"#de6d30\""
    end.

do_label([], _) ->
    "";
do_label([Node|Rest], N) ->
    "<tr><td bgcolor=" ++ rowColor(Node) ++ ">" ++ integer_to_list(N) ++ "</td><td bgcolor=" ++ rowColor(Node) ++ ">" ++ name(Node) ++ "</td></tr>" ++ do_label(Rest, N+1).

rowColor(Node) ->
    case node() of
        Node ->
            "\"#ff8d4f\"";
        _ ->
            "\"#ff8d4f\""
    end.
