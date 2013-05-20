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
%%%-------------------------------------------------------------------
%%% @author Malotte Westman Lönne <malotte@malotte.net>
%%% @copyright (C) 2012, Marina Westman Lönne
%%% @doc
%%%   rfzone exodm costumer server stub.
%%%
%%% Created : 15 May 2013 by Malotte Westman Lönne
%%% @end
%%%-------------------------------------------------------------------
-module(rfzone_customer_server).
-behaviour(gen_server).
-include("rfzone.hrl").

%% API
-export([start/1, 
	 stop/0,
	 receive_notification/1]).

%% gen_server callbacks
-export([init/1, 
	 handle_call/3, 
	 handle_cast/2, 
	 handle_info/2,
	 terminate/2, 
	 code_change/3]).

-define(SERVER, ?MODULE). 

-record(ctx,
	{
	  http::pid(),
	  client::pid()
	}).

start(Args) ->
    gen_server:start({local, ?SERVER}, ?MODULE, Args, []).

stop() ->
    gen_server:call(?SERVER, stop).

receive_notification(TimeOut)  ->
    gen_server:call(?SERVER, {notification, TimeOut}).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @end
%%--------------------------------------------------------------------
init(Args) ->
    ?dbg("init: args ~p", [Args]),
    HttpPort = proplists:get_value(http_port, Args, 8980),
    {ok, Http} = rfzone_http_server:start(HttpPort),
    {ok, #ctx {http = Http}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages.
%% Request can be the following:
%% <ul>
%% <li> notification - Waits for notification.</li>
%% <li> stop - Stops the application.</li>
%% </ul>
%%
%% @end
%%--------------------------------------------------------------------
handle_call({notification, TimeOut} = _Request, _From, Ctx) ->
    ?dbg("handle_call: request ~p", [_Request]),
    receive {http_request, _Body, _Sender} = HR ->
	    {reply, HR, Ctx}
    after TimeOut ->
	    {reply, timeout, Ctx}
    end;

handle_call(stop, _From, Ctx) ->
    ?dbg("stop:",[]),
    {stop, normal, ok, Ctx};

handle_call(_Request, _From, Ctx) ->
    ?dbg("handle_call: unknown request ~p", [_Request]),
    {reply, {error,bad_call}, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages.
%%
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, Ctx) ->
    ?dbg("handle_cast: unknown msg ~p", [_Msg]),
    {noreply, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages.
%% 
%% @end
%%--------------------------------------------------------------------
handle_info({http_request, _Body, _Sender} = HR, Ctx) ->
    ?dbg("handle_info: unexpected http_request ~p.",[HR]),
    {noreply, Ctx};
  
handle_info(_Info, Ctx) ->
    ?dbg("handle_info: unknown info ~p", [_Info]),
    {noreply, Ctx}.


%%--------------------------------------------------------------------
%% @private
%%--------------------------------------------------------------------
terminate(_Reason, _Ctx=#ctx {http = Http}) ->
    ?dbg("terminate: reason = ~p",[_Reason]),
    exit(Http, stop),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process ctx when code is changed
%%
%% @end
%%--------------------------------------------------------------------
-spec code_change(OldVsn::term(), Ctx::#ctx{}, Extra::term()) -> 
			 {ok, NewCtx::#ctx{}}.

code_change(_OldVsn, Ctx, _Extra) ->
    {ok, Ctx}.



