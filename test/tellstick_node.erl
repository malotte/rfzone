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
				      {use_serial_as_xnodeid, true},
				      {max_blksize, 7},
				      {vendor,?SEAZONE},
				      {debug, true}]),
    co_api:state(Serial, operational).

stop() ->
    Serial = serial(),
    co_api:stop(Serial),
    co_proc:stop(),
    can_udp:stop(tellstick_test),
    can_router:stop().

start_tellstick() ->
    tellstick_srv:start_link([{debug, true},
			      {config, "/Users/malotte/erlang/tellstick/test/tellstick_SUITE_data/tellstick.conf"},
%%			      {simulated, true},
			      {co_node, serial()}]).
   

stop_tellstick() ->
    tellstick_srv:stop().
