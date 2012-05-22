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
%%
%%  start wrapper
%%
%% @hidden
-module(tellstick_node).

%% Note: This directive should only be used in test suites.
-compile(export_all).

-define(SEAZONE, 16#2A1).

serial_os_env() ->
    case os:getenv("TELLSTICK_CO_SERIAL") of
	false ->  not_found;
	"0x"++SerX -> erlang:list_to_integer(SerX, 16);
	Ser -> erlang:list_to_integer(Ser, 10)
    end.

serial() ->
    case serial_os_env() of
	not_found ->
	    try ct:get_config(serial) of
		undefined -> 16#03000301;
		S -> S
	    catch
		%% Not running CT ??
		error: _Reason -> 16#03000301		    
	    end;
	S -> 
	   S
    end.

init() ->
    Serial = serial(),
    File = filename:join(code:priv_dir(canopen), "default.dict"),
    can_router:start(),
    can_udp:start(tellstick_test, 0),
    {ok, _PPid} = co_proc:start_link([{linked, false}]),
    {ok, _NPid} = co_api:start_link(Serial, 
				    [{linked, false},
				     {use_serial_as_xnodeid, true},
				     {load_last_saved, false},
				     {dict_file,File},
				     {max_blksize, 7},
				     {vendor,?SEAZONE},
				     {debug, true}]),
    co_api:save_dict(Serial),
    co_api:stop(Serial).

start() ->
    Serial = serial(),
    can_router:start(),
    can_udp:start(tellstick_test, 0),
    {ok, _PPid} = co_proc:start_link([{linked, false}]),
    {ok, _NPid} = co_api:start_link(Serial, 
				     [{linked, false},
				      {name, co_tellstick},
				      {use_serial_as_xnodeid, true},
				      {nmt_role, autonomous},
				      {max_blksize, 7},
				      {vendor,?SEAZONE},
				      {debug, true}]),
    
    {ok, _BPid} = bert_rpc_exec:start().

stop() ->
    Serial = serial(),
    co_api:stop(Serial),
    co_proc:stop(),
    can_udp:stop(tellstick_test),
    can_router:stop(),
    io:format("Stop bert server manually\n",[]).

start_tellstick() ->
    tellstick_srv:start_link([{linked, false},
			      {debug, true},
			      {config, "/Users/malotte/erlang/tellstick/test/tellstick_SUITE_data/tellstick.conf"},
			      {co_node, serial()}]).
   

stop_tellstick() ->
    tellstick_srv:stop().
