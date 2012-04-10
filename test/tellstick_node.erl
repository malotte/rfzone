%%
%%  start wrapper
%%
%% @hidden
-module(tellstick_node).

-export([init/0, start/0, stop/0]).
-export([serial/0, serial_os_env/0]).

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
    can_udp:start(0),
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
    can_udp:start(0),
    {ok, _PPid} = co_proc:start_link([{linked, false}]),
    {ok, _NPid} = co_api:start_link(Serial, 
				     [{linked, false},
				      {use_serial_as_xnodeid, true},
				      {max_blksize, 7},
				      {vendor,?SEAZONE},
				      {debug, true}]).

stop() ->
    Serial = serial(),
    co_api:stop(Serial),
    co_proc:stop(),
    can_router:stop().
