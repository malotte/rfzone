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
	 config_exodm/0,
	 config_exodm/2,
	 receive_notification/2,
	 start_receive_all/0,
	 stop_receive_all/0,
	 digital_output/3]).

%% gen_server callbacks
-export([init/1, 
	 handle_call/3, 
	 handle_cast/2, 
	 handle_info/2,
	 terminate/2, 
	 code_change/3]).

-import(rfzone_test_lib, [configure_rfzone_account/2,
			  notification_url/1,
			  verify_notification/3]).
-define(SERVER, ?MODULE). 

-record(ctx,
	{
	  state = single,
	  http::pid(),
	  client::pid()
	}).

start(Args) ->
    gen_server:start({local, ?SERVER}, ?MODULE, Args, []).

stop() ->
    gen_server:call(?SERVER, stop).

config_exodm() -> 
    config_exodm("rfzone.yang", notification_url(8980)).

config_exodm(Yang, Port) 
  when is_list(Yang), is_integer(Port) ->
    gen_server:call(?SERVER, {config_exodm, Yang, notification_url(Port)}).

receive_notification(Request, TimeOut) 
  when is_integer(TimeOut), TimeOut > 0 ->
    gen_server:call(?SERVER, {notification, Request, TimeOut}, TimeOut + 1000).

start_receive_all()  ->
    gen_server:cast(?SERVER, start_receive_all).

stop_receive_all()  ->
    gen_server:cast(?SERVER, stop_receive_all).

digital_output(Device, Channel, Action) ->
    gen_server:call(?SERVER, {digital_output, Device, Channel, Action}).
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
    exodm_json_api:set_exodmrc_dir(code:lib_dir(rfzone)), %% ??
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
handle_call({config_exodm, Yang, Url} = Req, _From, Ctx) ->
    ?dbg("handle_call: ~p",[Req]),
    Result = configure_rfzone_account(Yang, Url),
    {reply, Result, Ctx};

handle_call({notification, Request, TimeOut} = Notif, _From, Ctx) ->
    ?dbg("handle_call: notification ~p", [Notif]),
    receive {http_request, Body, Sender} = HR ->
	    ?dbg("handle_call: received ~p", [HR]),
	    Result = verify_notification(Request, Body, Sender),
	    {reply, Result, Ctx}
    after TimeOut ->
	    {reply, timeout, Ctx}
    end;

handle_call({digital_output, Device, Channel, Action} = Req, _From, Ctx) ->
    ?dbg("handle_call: ~p", [Req]),
    Result = exodm_json_api:json_request("rfzone:digital-output",
					 [{"device-id", Device},
					  {"item-id", 16#20001},
					  {"channel", Channel},
					  {"action", Action}],
					 integer_to_list(random()),
					 user),
    {reply, Result, Ctx};

handle_call(stop, _From, Ctx) ->
    ?dbg("handle_call: stop:",[]),
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
handle_cast(start_receive_all, Ctx) ->
    ?dbg("handle_cast: start_receive_all",[]),
    {noreply, Ctx#ctx {state = multi}};
handle_cast(stop_receive_all, Ctx) ->
    ?dbg("handle_cast: start_receive_all",[]),
    {noreply, Ctx#ctx {state = single}};
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
handle_info({http_request, Body, Sender} = HR, Ctx=#ctx {state = multi}) ->
    ?dbg("handle_info: expected http_request ~p.",[HR]),
    Result = verify_notification(any, Body, Sender),
    ?dbg("handle_info: verification result ~p.",[Result]),    
    {noreply, Ctx};
  
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



random() ->
    %% Initialize
    random:seed(now()),
    %% Retreive
    random:uniform(16#1000000).
