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
%%%   Tests rfzone including exodm.
%%%
%%% Created : 10 Apr 2012 by Malotte Westman Lönne
%%% @end
%%%-------------------------------------------------------------------
-module(rfzone_exo_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").

-define(EXO_ACCOUNT, "exodm").
-define(EXO_ADMIN, "exodm-admin").
-define(RF_ACCOUNT, "rfzone").
-define(RF_ADMIN, "rfzone-admin").
-define(RF_PASS, "wewontechcrunch2011").
-define(RF_USER, "mawe").
-define(RF_YANG, "rfzone.yang").
-define(RF_SET, "rfz").
-define(RF_TYPE, "rfz").
-define(RF_PROT, "rfz").
-define(RF_GROUP, "rfzg").
-define(RF_DEVICE, "rfzone1").
-define(RF_SERV_KEY, "1").
-define(RF_DEV_KEY, "2").

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
    [start_rfzone_exo,
     turn_on_off].

%%--------------------------------------------------------------------
%% @spec init_per_suite(Config0) ->
%%     Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%% Config0 = Config1 = [tuple()]
%% Reason = term()
%% @end
%%--------------------------------------------------------------------
init_per_suite(Config) ->
    install_exodm(),
    rfzone_node:init(),
    rfzone_node:start_exo(),
    Config.

%%--------------------------------------------------------------------
%% @spec end_per_suite(Config0) -> void() | {save_config,Config1}
%% Config0 = Config1 = [tuple()]
%% @end
%%--------------------------------------------------------------------
end_per_suite(_Config) ->
    rfzone_node:stop(),
    remove_system(),
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
    rfzone_srv:start_link([{debug, true}, 
			      {linked, false},
			      {reset, true},
			      {co_node, rfzone_node:serial()},
			      {config, ConfFile}]),
    %% Give rfzone time to reset
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
    rfzone_srv:stop(),
    ok.


%%--------------------------------------------------------------------
%% @spec start_rfzone() -> ok
%% @end
%%--------------------------------------------------------------------
start_rfzone(_Config) -> 
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
		  pdo1_tx, 16#6000, 11, <<1:32/little>>),
    co_api:notify({xnodeid, ct:get_config(source_node)}, 
		  pdo1_tx, 16#6000, 11, <<0:32/little>>),
    %% How verify ??
    timer:sleep(500),
    ct:pal("Turning off", []),
    co_api:notify({xnodeid, ct:get_config(source_node)}, 
		  pdo1_tx, 16#6000, 11, <<1:32/little>>),
    co_api:notify({xnodeid, ct:get_config(source_node)}, 
		  pdo1_tx, 16#6000, 11, <<0:32/little>>),
    %% How verify ??
    timer:sleep(500),
    ct:pal("Ready", []),
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
    rfzone_node:serial(). 

install_exodm() ->
    %% Work in local repo
    ct:pal("Using local repo ...",[]),
    ExodmDir = code:lib_dir(exodm),
    [] = os:cmd("cd " ++ ExodmDir ++ "; rm -rf nodes/dm"),

    %% Build and start node
    Res = os:cmd("cd " ++ ExodmDir ++ "; n=dm make node; n=dm make start"),
    ct:pal("dm node built and started.",[]),
    case string:tokens(Res, "\n") of
	[_MakeNode,
	 _ReadData,
	 _Cd,
	 "\t../../rel/exodm/bin/exodm start)"] -> ok;
	_Other ->
	    ct:pal("node result ~p", [string:tokens(Res, "\n")])
	    %% Fail ??
    end,
    NodesRes = os:cmd("cd " ++ ExodmDir ++ "; ls nodes"),
    true = lists:member(<<"dm">>, re:split(NodesRes, "\n", [])),
    timer:sleep(3000), %% Wait for node to get up

    ok.

configure_exodm(Config) ->
    exodm_json_api:parse_result(
      exodm_json_api:create_account(?RF_ACCOUNT, 
				    "tony@rogvall.se", 
				    ?RF_PASS, 
				    "RfZone"), 
      "ok"),
    
    File = filename:join(?config(data_dir, Config),?RF_YANG),
    case filelib:is_regular(File) of
	true -> ok;
	false -> ct:fail("File ~p not found", [File])
    end,
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
				       notification_url()),
      "ok"),
    exodm_json_api:parse_result(
      exodm_json_api:create_device_type(?RF_ACCOUNT, 
					?RF_TYPE,
					?RF_PROT),
      "ok"),
    
    exodm_json_api:parse_result(
      exodm_json_api:create_device_group(?RF_ACCOUNT, 
					 ?RF_GROUP,
					 notification_url()),
      "ok"),
    
     exodm_json_api:parse_result(
      exodm_json_api:create_device(?RF_ACCOUNT, 
				   ?RF_DEVICE,
				   ?RF_TYPE, 
				   ?RF_SERV_KEY, 
				   ?RF_DEV_KEY),
       "ok"),
     exodm_json_api:parse_result(
      exodm_json_api:add_config_set_members(?RF_ACCOUNT, 
					    [?RF_TYPE], 
					    [?RF_DEVICE]),
       "ok"),
     exodm_json_api:parse_result(
      exodm_json_api:add_device_group_members(?RF_ACCOUNT, 
					      [?RF_GROUP],
					      [?RF_DEVICE]),
      "ok").

remove_system() ->
    ExodmDir = code:lib_dir(exodm),
    Res2 = os:cmd("cd " ++ ExodmDir ++ "; n=dm make stop"),
    ct:pal("Res2 ~p", [Res2]),
    store_logs(ExodmDir),
    [] = os:cmd("cd " ++ ExodmDir ++ "; rm -rf nodes/dm").
	
store_logs(Exodm) ->
    case ct:get_config(log_dir) of
	undefined ->
	    %% Skip storing
	    ct:pal("No storing logs.",[]),
	    ok;
	test ->
	    %% Use repo, will be overwritten each test run
	    LogDir = filename:join([code:lib_dir(rfzone),"test"]),
	    ct:pal("Storing logs to ~p.",[LogDir]),
	    os:cmd("rm -rf " ++ filename:join([LogDir,"log"])),
	    [] = os:cmd("mv -f " ++
			    filename:join([Exodm, "nodes", "dm", "log"]) ++
			    " " ++ LogDir);
	Path when is_list(Path) ->
	    %% Use specified directory
	    case filelib:is_dir(Path) of
		true ->
		    ct:pal("Storing logs to ~p.",[Path]),
		    os:cmd("rm -rf " ++ filename:join([Path,"log"])),
		    [] = os:cmd("mv -f" ++
				    filename:join([Exodm, "nodes",
						   "dm", "log"]) ++
				    " "  ++ Path);
		false->
		    ct:pal("Not valid log dir ~p.",[Path])
	    end
    end.


    
notification_url() ->
    Port = ct:get_config(notification_port),
    "https://localhost:" ++ integer_to_list(Port) ++ "/callback".
