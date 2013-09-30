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
-include_lib("rfzone/include/rfzone.hrl").
-include("rfzone_test.hrl").

-import(rfzone_test_lib, [configure_rfzone_account/2,
			  json_notification/1]).


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
     gpio_interrupt].

%%--------------------------------------------------------------------
%% @spec init_per_suite(Config0) ->
%%     Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%% Config0 = Config1 = [tuple()]
%% Reason = term()
%% @end
%%--------------------------------------------------------------------
init_per_suite(Config) ->
    start_exo(), 
    close_old_nodes([dm_node()]),
    install_exodm(),
    rfzone_customer_server:start([{http_port, 
				   ct:get_config(notification_port)}]),
    Config.

%%--------------------------------------------------------------------
%% @spec end_per_suite(Config0) -> void() | {save_config,Config1}
%% Config0 = Config1 = [tuple()]
%% @end
%%--------------------------------------------------------------------
end_per_suite(_Config) ->
    rfzone_customer_server:stop(),
    remove_system(),
    close_old_nodes([dm_node()]),
    stop_exo(),
    ok.


%%--------------------------------------------------------------------
%% @spec init_per_testcase(TestCase, Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%% TestCase = atom()
%% Config0 = Config1 = [tuple()]
%% Reason = term()
%% @end
%%--------------------------------------------------------------------
init_per_testcase(TestCase, Config) ->
    ct:pal("Testcase: ~p", [TestCase]),    
    ConfFile = filename:join(?config(data_dir, Config), ct:get_config(conf)),
    rfzone_srv:reload(ConfFile),
    tc_init(TestCase, Config).

tc_init(gpio_interrupt, Config) ->
    configure_exodm(Config),
    Config;
tc_init(_TC, Config) ->
    Config.
    
%%--------------------------------------------------------------------
%% @spec end_per_testcase(TestCase, Config0) ->
%%               void() | {save_config,Config1} | {fail,Reason}
%% TestCase = atom()
%% Config0 = Config1 = [tuple()]
%% Reason = term()
%% @end
%%--------------------------------------------------------------------
end_per_testcase(TestCase, _Config) ->
    ct:pal("End testcase: ~p", [TestCase]),
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
%% @spec gpio_interrupt() -> ok
%% @end
%%--------------------------------------------------------------------
gpio_interrupt(_Config) ->
    RfZone = case whereis(rfzone_srv) of
		 Pid when is_pid(Pid) -> Pid;
		 _ -> ct:fail("No rfzone found !!",[])
	     end,

    {PinReg, Pin} = ct:get_config(gpio_pin),
    %% Simulate gpio interrupt
    RfZone ! {gpio_interrupt, PinReg, Pin, 1},
    {?RF_DEVICE1, PinReg, Pin, 1} = json_notification("gpio-interrupt"),

    %% Simulate gpio interrupt
    RfZone ! {gpio_interrupt, PinReg, Pin, 0},
    {?RF_DEVICE1, PinReg, Pin, 0} = json_notification("gpio-interrupt"),
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
		     "Get Config by C = ets:tab2list(config)."),
    ok.


serial() ->
    rfzone_node:serial(). 

install_exodm() ->
    %% Work in local repo
    ct:pal("Using local repo ...",[]),
    ExodmDir = code:lib_dir(exodm),
    [] = os:cmd("cd " ++ ExodmDir ++ "; rm -rf nodes/dm"),

    %% Build and start node
    Res = os:cmd("cd " ++ ExodmDir ++ "; n=dm make node; n=dm make start"), %%
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
    exodm_json_api:set_exodmrc_dir(?config(data_dir, Config)),
    Yang = filename:join(?config(data_dir, Config),?RF_YANG),
    case filelib:is_regular(Yang) of
	true -> ok;
	false -> ct:fail("File ~p not found", [Yang])
    end,
    configure_rfzone_account(Yang, notification_url()).

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

dm_node() ->
    list_to_atom("dm@" ++ own_host_string()).

own_host() ->
    list_to_atom(own_host_string()).

own_host_string() ->
    OwnNode = atom_to_list(node()),
    case string:tokens(OwnNode, "@") of
	[_Node, Host] -> Host;
	Other -> ct:fail("Not able to get host, got ~p", [Other])
    end.

close_old_nodes([]) ->
    ok;
close_old_nodes([OldNode | Rest]) ->
    case ct_rpc:call(OldNode, erlang, node, []) of
	{badrpc, nodedown} ->
	    %% Good :-)
	    ct:pal("Cleaning up: Node ~p not running - good!.", [OldNode]),
	    close_old_nodes(Rest);
	OldNode ->
	    %% Old node running, stop it !!
	    ct:pal("Cleaning up: Node ~p still running, trying to stop it",
		   [OldNode]),
	    ct_rpc:call(OldNode, init, stop, []),
	    timer:sleep(2000),
	    close_old_nodes([OldNode | Rest])
    end.

start_exo() ->
    Apps = [crypto, public_key, lager, ale, exo, bert, gproc, kvdb],
    call(Apps, start),
    ?ei("Started support apps ~p", [Apps]),
    application:load(exoport),
    SetUps = case application:get_env(exoport, '$setup_hooks') of
	       undefined -> [];
	       {ok, List} -> List
	     end,
    ?ei("exoport setup hooks ~p", [SetUps]),
    [erlang:apply(M,F,A) || {_Phase, {M, F, A}} <- SetUps],
    ?ei("exoport setup hooks executed.", []),
    call([exoport], start),
    ?ei("Started exoport", []),
    call([canopen, gpio, rfzone], start),%%spi
    ok.
    
stop_exo() ->
    Apps = [rfzone, gpio, canopen, exoport, kvdb, gproc, bert, exo, ale, lager],
    call(Apps, stop),
    ok.

call([], _F) ->
    ok;
call([App|Apps], F) ->
    ?ei("~p: ~p\n", [F,App]),
    case {F, application:F(App)} of
	{start, {error,{not_started,App1}}} ->
	    call([App1,App|Apps], F);
	{start, {error,{already_started,App}}} ->
	    call(Apps, F);
	{F, ok} ->
	    call(Apps, F);
	{_F, Error} ->
	    Error
    end.

