%%%---- BEGIN COPYRIGHT --------------------------------------------------------
%%%
%%% Copyright (C) 2007 - 2012, Rogvall Invest AB, <tony@rogvall.se>
%%%
%%% This software is licensed as described in the file COPYRIGHT, which
%%% you should have received as part of this distribution. The terms
%%% are also available at http://www.rogvall.se/docs/copyright.txt.
%%%
%%% You may opt to use, copy, modify, merge, publish, distribute and/or sell
%%% copies of the Software, and permit persons to whom the Software is
%%% furnished to do so, under the terms of the COPYRIGHT file.
%%%
%%% This software is distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY
%%% KIND, either express or implied.
%%%
%%%---- END COPYRIGHT ----------------------------------------------------------
%%% @author Malotte W Lönne <malotte@malotte.net>
%%% @copyright (C) 2012, Tony Rogvall
%%% @doc
%%%  RfZone WebService inets functions.
%%%
%%% @end

-module(rfzdemo_inets).


-export([start_link/0, stop/0, do/1]).

-include_lib("inets/include/httpd.hrl").
-include_lib("nitrogen_core/include/wf.hrl").
-include("rfzdemo.hrl").


%%% @doc This is the routing table.
routes() ->
    [{"/",          rfzdemo_index},
     {"/favicon.ico", static_file},
     {"/images",    static_file},
     {"/js",        static_file},
     {"/css",       static_file}
    ].

start_link() ->
    start_link(szweb:http_server()).

start_link(inets) ->
    inets:start(),
    {ok, Pid} = case start_inets_httpd() of
        {ok, _NewPid} = Reply -> 
            Reply;
        {error, {already_started, Ref}} ->
            inets:stop(httpd, Ref),
            start_inets_httpd()
    end,
    link(Pid),
    {ok, Pid}.

start_inets_httpd() ->
    inets:start(httpd,
                    [{port,          rfzdemo:port()},
                     {server_name,   rfzdemo:servername()},
	             {bind_address,  rfzdemo:ip()},
                     {server_root,   "."},
                     {document_root, rfzdemo:docroot()},
	             {keep_alive, true},
		     {keep_alive_timeout, 600},
                     {modules,       [?MODULE]},
                     {mime_types,    [{"css",  "text/css"},
				      {"js",   "text/javascript"},
				      {"html", "text/html"}]}
    ]). 
   
stop() ->
    httpd:stop_service({any, rfzdemo:port()}),
    ok.

do(_Info=#mod{method = "GET", 
	      request_uri = "/$nitrogen/" ++ File,
	      http_version = HttpVersion,
	      parsed_header = Header}) ->
    %% Get nitrogen files from nitrogen_core
    ?dbg("do: nitrogen file ~p",  [File]),
    NitrogenFile = filename:join([code:lib_dir(nitrogen_core), "www", File]),
    {Etag, Size, LastModified} = file_data(NitrogenFile),
    case lists:keyfind("if-none-match", 1, Header) of
	{"if-none-match", Etag} ->
	    ?dbg("do: file ~p already sent",  [NitrogenFile]),
	    {proceed, [{response, {response,
				   lists:keystore(code, 1, Header, {code, 304}),
				   nobody}}]};
	_NoMatch ->
	    send_file(NitrogenFile, Etag, Size, LastModified, HttpVersion)
    end;
do(Info=#mod{request_uri = File}) ->
    ?dbg("do: file ~p",  [File]),
    put(gettext_language, "sv"),
    RequestBridge = simple_bridge:make_request(inets_request_bridge, Info),
    ResponseBridge = simple_bridge:make_response(inets_response_bridge, Info),
    nitrogen:init_request(RequestBridge, ResponseBridge),
    replace_route_handler(),
    Reply = nitrogen:run(),
    case File of
     	"/favicon.ico" -> 
     	    ?dbg("do: info ~p",  [Info]),
     	    ?dbg("do: request ~p", [RequestBridge]),
     	    ?dbg("do: response ~p", [ResponseBridge]),
     	    ?dbg("do: reply = ~p", [Reply]);
     	_ -> nop
    end,
    Reply.

send_file(File, Etag, Size, LastModified, HttpVersion) ->
    case file:read_file(File) of
	{ok, Binary} ->
	    ?dbg("send: file ~p read.",  [File]),
	    Header = header(File, 200, Etag, Size, LastModified, HttpVersion),
	    ?dbg("send: header ~p.", [Header]),
	    {proceed, [{response, {response,
				   Header, 
				   [Binary]}}]};
	{error, Reason} ->
	    ?ee("sweb_inets: read of file ~s, failed, reason ~p",
		[File, Reason]),
	    %% This might happen if nitrogen has changed file names
	    %% or directory structure
	    {proceed, [{response, {response,
				   [{code, 404}], 
				   nobody}}]}
    end.

replace_route_handler() ->
    wf_handler:set_handler(named_route_handler, routes()).

header(File, Code, Etag, Size, LastModified, HttpVersion) ->
    lists:flatten([[{code, Code},
		    {cache_control, "max-age=3600"},
		    {content_length, Size}],
		   content_type(File),
		   LastModified,
		   etag(HttpVersion, Etag)]).

content_type(File) ->
    [{content_type, content_type1(filename:extension(File))}].
content_type1(".js") ->
    "text/javascript";
content_type1(".css") ->
    "text/css".

etag("HTTP/1.1", Etag) -> [{etag, Etag}];
etag(_Version, _Etag) -> [].
    
file_data(File)->
    {ok, FileInfo} = file:read_file_info(File), 
    LastModified = 
	case catch httpd_util:rfc1123_date(FileInfo#file_info.mtime) of
	    Date when is_list(Date) -> [{last_modified, Date}];
	    _ -> []
	end,
    Etag = httpd_util:create_etag(FileInfo),    
    Size = integer_to_list(FileInfo#file_info.size),
    {Etag, Size, LastModified}.
