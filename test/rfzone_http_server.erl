%%%---- BEGIN COPYRIGHT -------------------------------------------------------
%%%
%%% Copyright (C) 2012 Feuerlabs, Inc. All rights reserved.
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at http://mozilla.org/MPL/2.0/.
%%%
%%%---- END COPYRIGHT ---------------------------------------------------------
%%% @author Marina Westman Lönne <malotte@malotte.net>
%%% @doc
%%%   rfzone callback http server.
%%%
%%% Created : 2012 by Marina Westman Lönne 
%%% @end

-module(rfzone_http_server).


-include_lib("exo/include/exo_http.hrl").
-include_lib("lager/include/log.hrl").

-export([start/1,
	 start_link/1,
	 handle_body/3]).

-import(exo_http_server, [response/5]).

%%-----------------------------------------------------------------------------
%% @doc
%%  Starts an http server with handle request callback to this module.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec start(Port::integer()) -> 
		   {ok, ChildPid::pid()} |
		   {error, Reason::term()}.

start(Port) when is_integer(Port) ->
    ct:pal("rfzone_http_server: start: port ~p",[Port]),
    exo_http_server:start(Port, [{request_handler, {?MODULE, handle_body}}]).

%%-----------------------------------------------------------------------------
%% @doc
%%  Starts an http server with handle request callback to this module.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec start_link(Port::integer()) -> 
		   {ok, ChildPid::pid()} |
		   {error, Reason::term()}.

start_link(Port) ->
    ct:pal("rfzone_http_server: start: port ~p",[Port]),
    exo_http_server:start_link(Port, [{request_handler, 
				       {?MODULE, handle_body}}]).

%%-----------------------------------------------------------------------------
%% @doc
%%  Callback to handle a request body.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec handle_body(Socket::term(), 
		  Request::#http_request{}, 
		  Body::binary()) ->
			 ok |
			 stop |
			 {error, Reason::term()}.

handle_body(Socket, Request, Body) ->
    ?debug("rfzone_http_server: handle_body: body ~s.",[Body]),
    ct:pal("rfzone_http_server: handle_body: body ~s.",[Body]),
    Url = Request#http_request.uri,
    if Request#http_request.method == 'GET',
       Url#url.path == "/quit" ->
	    ?debug("rfzone_http_server: handle_body: quit.",[]),
	    ct:pal("rfzone_http_server: handle_body: quit.",[]),
	    response(Socket, "close", 200, "OK", "QUIT"),
	    exo_socket:shutdown(Socket, write),
	    stop;
       Url#url.path == "/test" ->
	    ?debug("rfzone_http_server: handle_body: test.",[]),
	    ct:pal("rfzone_http_server: handle_body: test.",[]),
	    response(Socket, undefined, 200, "OK", "OK"),
	    ok;
       Url#url.path == "/callback" ->
	    ?debug("rfzone_http_server: handle_body: callback.",[]),
	    ct:pal("rfzone_http_server: handle_body: callback.",[]),
	    case whereis(rfzone_customer_server) of
		Pid when is_pid(Pid) ->
		    ?debug("rfzone_http_server: handle_body: send to ~p.",[Pid]),		    ct:pal("rfzone_http_server: handle_body: send to ~p.",[Pid]),
		    Pid ! {http_request, Body, self()};
		_Other ->
		    ?debug("rfzone_http_server: handle_body: no one to send to.",[]),
		    ct:pal("rfzone_http_server: handle_body: no one to send to.",[]),
		    do_nothing
	    end,
	    receive
		Reply ->
		    ?debug("rfzone_http_server: handle_body: send reply ~p.",
			   [Reply]),
		    ct:pal("rfzone_http_server: handle_body: send reply ~p.",
			   [Reply]),
		    response(Socket, undefined, 200, "OK", lists:flatten(Reply))
	    after 1000 ->
		    response(Socket, undefined, 200, "OK", "OK")
	    end,
	    ok;
       true ->
	    ?debug("rfzone_http_server: handle_body: path ~p.",[Url#url.path]),
	    ct:pal("rfzone_http_server: handle_body: path ~p.",[Url#url.path]),
	    exo_http_server:response(Socket, undefined, 404, "Not Found", 
				     "Object not found"),
	    ok
    end.
	    
