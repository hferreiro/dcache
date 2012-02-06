function getXMLHttpRequest() {
    var xmlHttpReq = false;
    if (window.XMLHttpRequest) {
        xmlHttpReq = new XMLHttpRequest();
    }
    else if (window.ActiveXObject) {
        xmlHttpReq = new ActiveXObject("Microsoft.XMLHTTP");
    }
    return xmlHttpReq;
}

function xmlhttpPost(xmlHttpReq, URL, callback) {
    xmlHttpReq.open('POST', URL, true);
    xmlHttpReq.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
    xmlHttpReq.onreadystatechange = function() {
                                        if (xmlHttpReq.readyState == 4) {
                                            callback(xmlHttpReq.responseText);
                                        }
                                    }
    xmlHttpReq.send('');  // TODO: tomar los parametros opcionales por argumento y mandarlos en el POST
}

xmlHttpReqGraph = getXMLHttpRequest();
function updateGraph() {
    xmlhttpPost(xmlHttpReqGraph, "/graph.yaws",
            function(result) {
                document.getElementById("graph").innerHTML = result;
                setTimeout("updateGraph()", 5000);
            });
}

xmlHttpReqPlayList = getXMLHttpRequest();
function updatePlayListClient(node) {
    xmlhttpPost(xmlHttpReqPlayList, "/playlistcliente.yaws?node=" + node,
            function(result) {
                document.getElementById("playlist-cliente").innerHTML = result;
                setTimeout("updatePlayListClient(" + node + ")", 2000);
            });
}

xmlHttpReqPlayListAdmin = getXMLHttpRequest();
function updatePlayListAdmin(node) {
    xmlhttpPost(xmlHttpReqPlayListAdmin, "/playlistadmin.yaws?node=" + node,
            function(result) {
                document.getElementById("playlist").innerHTML = result;
                setTimeout("updatePlayListAdmin(" + node + ")", 5000);
            });
}
