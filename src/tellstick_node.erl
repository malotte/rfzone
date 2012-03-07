%%
%%  start wrapper
%%
%%
-module(tellstick_node).

-export([init/0, start/0, stop/0]).
-export([serial/0, serial_os_env/0]).

-define(SEAZONE, 16#2A1).

serial_os_env() ->
    case os:getenv("TELLSTICK_CO_SERIAL") of
	false ->  16#03000301;
	"0x"++SerX -> erlang:list_to_integer(SerX, 16);
	Ser -> erlang:list_to_integer(Ser, 10)
    end.

serial() ->
    File = filename:join(code:priv_dir(tellstick), "tellstick.conf"),
    case file:consult(File) of
	{ok,Conf} -> 
	    case proplists:lookup(serial, Conf) of
		{serial,Serial} ->
		    Serial;
		none ->
		    serial_os_env()
	    end;
	{error,_Reason} ->
	    io:format("warning: config file tellstick.conf not found\n"),
	    serial_os_env()	    
    end.
    
init() ->
    Serial = serial(),
    File = filename:join(code:priv_dir(canopen), "default.dict"),
    can_router:start(),
    can_udp:start(0),
    {ok, _PPid} = co_proc:start_link([]),
    {ok, _NPid} = co_node:start_link([{serial,Serial}, 
				      {options, [{use_serial_as_xnodeid, true},
						 %% {nodeid, 7},
						 {load_default, false},
						 {dict_file,File},
						 {max_blksize, 7},
						 {vendor,?SEAZONE},
						 {debug, true}]}]),
    co_node:save_dict(Serial),
    co_node:stop(Serial).

start() ->
    Serial = serial(),
    can_router:start(),
    can_udp:start(0),
    {ok, _PPid} = co_proc:start_link([]),
    {ok, _NPid} = co_node:start_link([{serial,Serial}, 
				      {options, [{use_serial_as_xnodeid, true},
						 %% {nodeid, 7},
						 {max_blksize, 7},
						 {vendor,?SEAZONE},
						 {debug, true}]}]).

stop() ->
    Serial = serial(),
    co_node:stop(Serial),
    co_proc:stop(),
    can_router:stop().
