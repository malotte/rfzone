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
%%%
%%% Created : 10 Apr 2012 by Malotte Westman Lönne
%%% @end
%%%-------------------------------------------------------------------
-module(tellstick_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").

%%--------------------------------------------------------------------
%% @spec suite() -> Info
%% Info = [tuple()]
%% @end
%%--------------------------------------------------------------------
suite() ->
    [{timetrap,{seconds,30}}].

%%--------------------------------------------------------------------
%% @spec all() -> GroupsAndTestCases | {skip,Reason}
%% GroupsAndTestCases = [{group,GroupName} | TestCase]
%% GroupName = atom()
%% TestCase = atom()
%% Reason = term()
%% @end
%%--------------------------------------------------------------------
all() -> 
    [start_tellstick,
     turn_on_off].

%%--------------------------------------------------------------------
%% @spec init_per_suite(Config0) ->
%%     Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%% Config0 = Config1 = [tuple()]
%% Reason = term()
%% @end
%%--------------------------------------------------------------------
init_per_suite(Config) ->
    tellstick_node:init(),
    tellstick_node:start(),
    Config.

%%--------------------------------------------------------------------
%% @spec end_per_suite(Config0) -> void() | {save_config,Config1}
%% Config0 = Config1 = [tuple()]
%% @end
%%--------------------------------------------------------------------
end_per_suite(_Config) ->
    tellstick_node:stop(),
    ok.


%%--------------------------------------------------------------------
%% @spec init_per_testcase(TestCase, Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%% TestCase = atom()
%% Config0 = Config1 = [tuple()]
%% Reason = term()
%% @end
%%--------------------------------------------------------------------
init_per_testcase(_TestCase, Config) ->
    ct:pal("Testcase: ~p", [_TestCase]),
    ConfFile = filename:join(?config(data_dir, Config), ct:get_config(conf)),
    tellstick_srv:start_link([{debug, true}, 
			      {linked, false},
			      {reset, true},
			      {co_node, tellstick_node:serial()},
			      {config, ConfFile}]),
    %% Give tellstick time to reset
    Config.

%%--------------------------------------------------------------------
%% @spec end_per_testcase(TestCase, Config0) ->
%%               void() | {save_config,Config1} | {fail,Reason}
%% TestCase = atom()
%% Config0 = Config1 = [tuple()]
%% Reason = term()
%% @end
%%--------------------------------------------------------------------
end_per_testcase(_TestCase, _Config) ->
    tellstick_srv:stop(),
    ok.


%%--------------------------------------------------------------------
%% @spec start_tellstick() -> ok
%% @end
%%--------------------------------------------------------------------
start_tellstick(_Config) -> 
    %% Done in init_per_testcase()
    timer:sleep(200),
    ok.

%%--------------------------------------------------------------------
%% @spec turn_on() -> ok
%% @end
%%--------------------------------------------------------------------
turn_on_off(_Config) ->
    %% Springback requires on and off
    ct:pal("Turning on", []),
    co_api:notify({xnodeid, ct:get_config(source_node)}, 
		  pdo1_tx, 16#6000, 9, <<1:32/little>>),
    co_api:notify({xnodeid, ct:get_config(source_node)}, 
		  pdo1_tx, 16#6000, 9, <<0:32/little>>),
    %% How verify ??
    timer:sleep(500),
    ct:pal("Turning off", []),
    co_api:notify({xnodeid, ct:get_config(source_node)}, 
		  pdo1_tx, 16#6000, 9, <<1:32/little>>),
    co_api:notify({xnodeid, ct:get_config(source_node)}, 
		  pdo1_tx, 16#6000, 9, <<0:32/little>>),
    %% How verify ??
    timer:sleep(500),
    ct:pal("Ready", []),
    ok.

%%--------------------------------------------------------------------
%% @spec turn_off() -> ok
%% @end
%%--------------------------------------------------------------------
turn_off(_Config) ->
    %% Springback requires on and off
    ok.

%%--------------------------------------------------------------------
%% @spec break(Config) -> ok 
%% @doc 
%% Dummy test case to have a test environment running.
%% Stores Config in ets table.
%% @end
%%--------------------------------------------------------------------
break(Config) ->
    ets:new(config, [set, public, named_table]),
    ets:insert(config, Config),
    test_server:break("Break for test development\n" ++
		     "Get Config by ets:tab2list(config)"),
    ok.


serial() ->
    tellstick_node:serial(). 
