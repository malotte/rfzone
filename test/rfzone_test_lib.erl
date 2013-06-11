%%%---- BEGIN COPYRIGHT --------------------------------------------------------
%%%
%%% Copyright (C) 2007 - 2013, Rogvall Invest AB, <tony@rogvall.se>
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
%%% @copyright (C) 2013, Marina Westman Lönne
%%% @doc
%%%   Common test functions.
%%%
%%% Created : May 2013 by Malotte Westman Lönne
%%% @end
%%%-------------------------------------------------------------------
-module(rfzone_test_lib).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include("rfzone.hrl").
-include("rfzone_test.hrl").

configure_rfzone_account(File, Url) ->
       exodm_json_api:parse_result(
      exodm_json_api:create_account(?RF_ACCOUNT, 
				    "tony@rogvall.se", 
				    ?RF_PASS, 
				    "RfZone"), 
      "ok"),
    
    exodm_json_api:parse_result(
      exodm_json_api:create_yang_module(?RF_ACCOUNT, 
					?RF_YANG,
					"user",
					File),
      "ok"),
    
    exodm_json_api:parse_result(
      exodm_json_api:create_config_set(?RF_ACCOUNT, 
				       ?RF_SET,
				       ?RF_YANG, 
				       Url),
      "ok"),
    exodm_json_api:parse_result(
      exodm_json_api:create_device_type(?RF_ACCOUNT, 
					?RF_TYPE,
					?RF_PROT),
      "ok"),
    
    exodm_json_api:parse_result(
      exodm_json_api:create_device_group(?RF_ACCOUNT, 
					 ?RF_GROUP,
					 Url),
      "ok"),
    
    configure_device(?RF_DEVICE1, ?RF_DEVICE_NR1),
    configure_device(?RF_DEVICE2, ?RF_DEVICE_NR2).

configure_device(Device, Number) ->    
     exodm_json_api:parse_result(
      exodm_json_api:create_device(?RF_ACCOUNT, 
				   Device,
				   ?RF_TYPE, 
				   ?RF_SERV_KEY, 
				   ?RF_DEV_KEY,
				   Number),
       "ok"),
     exodm_json_api:parse_result(
      exodm_json_api:add_config_set_members(?RF_ACCOUNT, 
					    [?RF_SET], 
					    [Device]),
       "ok"),
     exodm_json_api:parse_result(
      exodm_json_api:add_device_group_members(?RF_ACCOUNT, 
					      [?RF_GROUP],
					      [Device]),
      "ok").

json_notification(Request) ->
    rfzone_customer_server:receive_notification(Request, 3000).

verify_notification(Request, Body, Sender) ->
    Callback = "rfzone:" ++ Request,
    String = binary_to_list(Body),
    {ok, {struct, Values}} = json2:decode_string(String),
    ?v({"jsonrpc","2.0"}, lists:keyfind("jsonrpc",1,Values)),
    case lists:keyfind("method",1,Values) of
	{"method", Callback} 
	     when Callback =:= "rfzone:gpio-interrupt" ->
	    {"id",TransIdString} = lists:keyfind("id",1,Values),
	    Sender ! json_ok(TransIdString),
	    {"params", {struct, Params}} = lists:keyfind("params",1, Values),
	    {"device-id", DeviceId} = lists:keyfind("device-id",1,Params),
	    {"pin-register", PinReg} = lists:keyfind("pin-register",1,Params),
	    {"pin", Pin} = lists:keyfind("pin",1,Params),
	    {"value", Value} = lists:keyfind("value",1,Params),
	    {DeviceId, PinReg, Pin, Value};
	{"method", Callback} 
	     when Callback =:= "rfzone:piface-interrupt" ->
	    {"id",TransIdString} = lists:keyfind("id",1,Values),
	    Sender ! json_ok(TransIdString),
	    {"params", {struct, Params}} = lists:keyfind("params",1, Values),
	    {"device-id", DeviceId} = lists:keyfind("device-id",1,Params),
	    {"pin", Pin} = lists:keyfind("pin",1,Params),
	    {"value", Value} = lists:keyfind("value",1,Params),
	    {DeviceId, Pin, Value};
	{"method", _Any} when Request =:= any ->
	    ct:pal("~p notification: ~p",[Request, Body]),
	    {"id",TransIdString} = lists:keyfind("id",1,Values),
	    Sender ! json_ok(TransIdString),
	    ok;
	{"method", _Other} ->
	    %% See if unknown (while developing)
	    if Callback == unknown ->
		    ct:pal("~p notification: ~p",[Request, Body]),
		    ok;
	       true ->
		    %% Something is wrong
		    ct:fail("~p unexpected notification: ~p",[Request, Body])
	    end
    end.

json_ok(TransId) ->
    json2:encode({struct, [{"jsonrpc", "2.0"},
			   {"id", TransId},
			   {"result", {struct,[{"result", "0"}]}}]}).
    

notification_url(Port) ->
    "https://localhost:" ++ integer_to_list(Port) ++ "/callback".
