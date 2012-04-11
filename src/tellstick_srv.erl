%%%-------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @author Malotte Westman Lönne <malotte@malotte.net>
%%% @copyright (C) 2012, Tony Rogvall
%%% @doc
%%%    Tellstick control server.
%%%    For detailed description of the functionality see the overview.
%%%
%%% Created:  5 Jul 2010 by Tony Rogvall 
%%% @end
%%%-------------------------------------------------------------------
-module(tellstick_srv).

-behaviour(gen_server).

-include_lib("can/include/can.hrl").
-include_lib("canopen/include/canopen.hrl").
-include_lib("canopen/include/co_app.hrl").
-include_lib("canopen/include/co_debug.hrl").

%% API
-export([start_link/1, 
	 stop/0]).
-export([reload/0, 
	 reload/1]).

%% gen_server callbacks
-export([init/1, 
	 handle_call/3, 
	 handle_cast/2, 
	 handle_info/2,
	 terminate/2, 
	 code_change/3]).

%% Testing
-export([start/0, 
	 debug/1, 
	 dump/0]).

-define(SERVER, ?MODULE). 
-define(COMMANDS,[{{?MSG_POWER_ON, 0}, ?INTEGER, 0},
		  {{?MSG_POWER_OFF, 0}, ?INTEGER, 0},
		  {{?MSG_DIGITAL, 0}, ?INTEGER, 0},
		  {{?MSG_ANALOG, 0}, ?INTEGER, 0},
		  {{?MSG_ENCODER, 0}, ?INTEGER, 0}]).


%% 
-record(conf,
	{
	  product,
	  device,
	  items
	}).

%% Controlled item
-record(item,
	{
	  %% Remote ID
	  rid,    %% remote id
	  rchan,  %% remote channel
	  lchan,  %% local channel

	  %% Device ID
	  type,     %% nexa, ikea ...
	  unit,     %% serial/unit/house code
	  chan,     %% device channel
	  flags=[], %% device flags

	  %% State
	  active = false,  %% off
	  level = 0        %% dim level
	}).

%% Loop data
-record(ctx,
	{
	  co_node, %% any identity of co_node i.e. serial | name | nodeid ...
	  node_id, %% nodeid | xnodeid of co_node, needed in notify
	           %% should maybe be fetched when needed instead of stored in loop data ??
	  items    %% controlled items
	}).

%%%===================================================================
%%% API
%%%===================================================================
%%--------------------------------------------------------------------
%% @doc
%% Starts the server.
%% Loads configuration from File.
%% @end
%%--------------------------------------------------------------------
-spec start_link(Opts::list(term())) -> 
			{ok, Pid::pid()} | 
			ignore | 
			{error, Error::term()}.

start_link(Opts) ->
    F =	case proplists:get_value(linked,Opts,true) of
	    true -> start_link;
	    false -> start
	end,
    
    gen_server:F({local, ?SERVER}, ?MODULE, Opts, []).


%%--------------------------------------------------------------------
%% @doc
%% Stops the server.
%% @end
%%--------------------------------------------------------------------
-spec stop() -> ok | {error, Error::term()}.

stop() ->
    gen_server:call(?SERVER, stop).

%%--------------------------------------------------------------------
%% @doc
%% Reloads the default configuration file (tellstick.conf) from the 
%% default location (the applications priv-dir).
%% @end
%%--------------------------------------------------------------------
-spec reload() -> ok | {error, Error::term()}.

reload() ->
    File = filename:join(code:priv_dir(tellstick), "tellstick.conf"),
    gen_server:call(?SERVER, {reload, File}).

%%--------------------------------------------------------------------
%% @doc
%% Reloads the configuration file.
%% @end
%%--------------------------------------------------------------------
-spec reload(File::atom()) -> 
		    ok | {error, Error::term()}.

reload(File) ->
    gen_server:call(?SERVER, {reload, File}).

%% Test functions
%% @private
dump() ->
    gen_server:call(?SERVER, dump).

%% @private
debug(TrueOrFalse) when is_boolean(TrueOrFalse) ->
    gen_server:call(?SERVER, {debug, TrueOrFalse}).

%% @private
start() ->
    start_link([{debug, true},{co_node, tellstick_node:serial()}, {simulated, true}]).
   

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @end
%%--------------------------------------------------------------------
-spec init(Args::list(term())) -> 
		  {ok, Ctx::record()} |
		  {ok, Ctx::record(), Timeout::timeout()} |
		  ignore |
		  {stop, Reason::term()}.

init(Args) ->
    Dbg = proplists:get_value(debug, Args, false),
    put(dbg, Dbg),

    case proplists:get_value(co_node, Args) of
	undefined ->
	    ?dbg(?SERVER,"init: No CANOpen node given.", []),
	    {stop, no_co_node};
	CoNode ->
	    Simulated = proplists:get_value(simulated, Args, false),
	    FileName = proplists:get_value(config, Args, "tellstick.conf"),
	    ConfFile =  full_filename(FileName),
	    ?dbg(?SERVER,"init: File = ~p", [ConfFile]),

	    case load_config(ConfFile) of
		{ok, Conf} ->
		    if Simulated ->
			    ?dbg(?SERVER,"init: Executing in simulated mode.",[]), 
			    {ok, _Pid} = tellstick_drv:start_link([{device,simulated},
							      {debug, get(dbg)}]);
		       Conf#conf.device =:= undefined ->
			    ?dbg(?SERVER,"init: Driver undefined.", []),
			    {ok, _Pid} = tellstick_drv:start();
		       true ->
			    Device = Conf#conf.device,
			    ?dbg(?SERVER,"init: Device = ~p.", [Device]),
			    {ok, _Pid} = tellstick_drv:start_link([{device,Device},
								   {debug, get(dbg)}])
		    end,
		    {ok, _Dict} = co_api:attach(CoNode),
		    Nid = co_api:get_option(CoNode, id),
		    subscribe(CoNode),
		    case proplists:get_value(reset, Args, false) of
			true -> reset_items(Conf#conf.items);
			false -> do_nothing
		    end,
		    power_on(Nid, Conf#conf.items),
		    process_flag(trap_exit, true),
		    {ok, #ctx { co_node = CoNode, 
				node_id = Nid, 
				items=Conf#conf.items }};
		Error ->
		    ?dbg(?SERVER,
			 "init: Not possible to load configuration file ~p.",
			 [ConfFile]),
		    {stop, Error}
	    end
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages.
%% Request can be the following:
%% <ul>
%% <li> {get, Index, SubInd} - Returns the value for Index:SubInd.</li>
%% <li> {set, Index, SubInd, Value} - Sets the value for Index:SubInd.</li>
%% <li> reload - Reloads the configuration file.</li>
%% <li> dump - Writes loop data to standard out (for debugging).</li>
%% <li> debug - Turns on/off debug output. </li>
%% <li> stop - Stops the application.</li>
%% </ul>
%%
%% @end
%%--------------------------------------------------------------------
-type call_request()::
	{reload, File::atom()} |
	{new_co_node, Id::term()} |
	dump |
	{debug, TrueOrFalse::boolean()} |
	stop.

-spec handle_call(Request::call_request(), From::pid(), Ctx::#ctx{}) ->
			 {reply, Reply::term(), Ctx::#ctx{}} |
			 {reply, Reply::term(), Ctx::#ctx{}, Timeout::timeout()} |
			 {noreply, Ctx::#ctx{}} |
			 {noreply, Ctx::#ctx{}, Timeout::timeout()} |
			 {stop, Reason::atom(), Reply::term(), Ctx::#ctx{}} |
			 {stop, Reason::atom(), Ctx::#ctx{}}.


handle_call({reload, File}, _From, Ctx=#ctx {node_id = Nid, items = OldItems}) ->
    ?dbg(?SERVER,"reload ~p",[File]),
    ConfFile = full_filename(File),
    case load_config(ConfFile) of
	{ok,Conf} ->
	    NewItems = Conf#conf.items,
	    ItemsToAdd = lists:usort(NewItems) -- lists:usort(OldItems),
	    ItemsToRemove = lists:usort(OldItems) -- lists:usort(NewItems),
	    power_on(Nid, ItemsToAdd),
	    power_off(Nid, ItemsToRemove),
	    {reply, ok, Ctx#ctx {items = NewItems}};
	Error ->
	    {reply, Error, Ctx}
    end;

handle_call({new_co_node, NewCoNode}, _From, Ctx=#ctx {co_node = NewCoNode}) ->
    %% No change
    {reply, ok, Ctx};
handle_call({new_co_node, NewCoNode}, _From, Ctx=#ctx {co_node = OldCoNode}) ->
    unsubscribe(OldCoNode),
    co_api:detach(OldCoNode),
    co_api:attach(NewCoNode),
    subscribe(NewCoNode),
    Nid = co_api:get_option(NewCoNode, id),
    {reply, ok, Ctx#ctx {co_node = NewCoNode, node_id = Nid }};

handle_call(dump, _From, Ctx=#ctx {co_node = CoNode, node_id = Nid, items = Items}) ->
    io:format("Ctx: CoNode = ~11.16.0#, ", [CoNode]),
    io:format("NodeId = ~11.16.0#, Items=\n", [Nid]),
    lists:foreach(fun(Item) -> print_item(Item) end, Items),
    {reply, ok, Ctx};

handle_call({debug, TrueOrFalse}, _From, Ctx) ->
    put(dbg, TrueOrFalse),
    {reply, ok, Ctx};

handle_call(stop, _From, Ctx=#ctx {co_node = CoNode}) ->
    ?dbg(?SERVER,"stop:",[]),
    case co_api:alive(CoNode) of
	true ->
	    unsubscribe(CoNode),
	    ?dbg(?SERVER,"stop: unsubscribed.",[]),
	    co_api:detach(CoNode);
	false -> 
	    do_nothing %% Not possible to detach and unsubscribe
    end,
    ?dbg(?SERVER,"stop: detached.",[]),
    {stop, normal, ok, Ctx};

handle_call(_Request, _From, Ctx) ->
    {reply, {error,bad_call}, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages.
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_cast(Msg::term(), Ctx::record()) -> 
			 {noreply, Ctx::record()} |
			 {noreply, Ctx::record(), Timeout::timeout()} |
			 {stop, Reason::term(), Ctx::record()}.

handle_cast({extended_notify, _Index, Frame}, Ctx) ->
    ?dbg(?SERVER,"handle_cast: received notify with frame ~w.",[Frame]),
    %% Check index ??
    COBID = ?CANID_TO_COBID(Frame#can_frame.id),
    <<_F:1, _Addr:7, Ix:16/little, Si:8, Data:4/binary>> = Frame#can_frame.data,
    ?dbg(?SERVER,"handle_cast: index = ~.16.0#:~w, data = ~w.",[Ix, Si, Data]),
    try co_codec:decode(Data, unsigned32) of
	{Value, _Rest} ->
	    handle_notify({COBID, Ix, Si, Value}, Ctx)
    catch
	error:_Reason ->
	    ?dbg(?SERVER,"handle_cast: decode failed, reason ~p.",[_Reason]),
	    {noreply, Ctx}
    end;
handle_cast(_Msg, Ctx) ->
    {noreply, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages.
%% 
%% @end
%%--------------------------------------------------------------------
-type info()::
	{notify, RemoteId::integer(), Index:: integer(), SubInd::integer(), Value::term()} |
	{'EXIT', Pid::pid(), co_node_terminated}.

-spec handle_info(Info::info(), Ctx::record()) -> 
			 {noreply, Ctx::record()} |
			 {noreply, Ctx::record(), Timeout::timeout()} |
			 {stop, Reason::term(), Ctx::record()}.

handle_info({'EXIT', _Pid, co_node_terminated}, Ctx) ->
    ?dbg(?SERVER,"handle_info: co_node terminated.",[]),
    {stop, co_node_terminated, Ctx};    
handle_info(Info, Ctx) ->
    ?dbg(?SERVER,"handle_info: Unknown Info ~p", [Info]),
    {noreply, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @end
%%--------------------------------------------------------------------
-spec terminate(Reason::term(), Ctx::record()) -> 
		       ok.

terminate(Reason, _Ctx) ->
    ?dbg(?SERVER,"terminate: Reason = ~p",[Reason]),
    tellstick_drv:stop(),
    ?dbg(?SERVER,"terminate: driver stopped.",[]),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process ctx when code is changed
%%
%% @end
%%--------------------------------------------------------------------
-spec code_change(OldVsn::term(), Ctx::record(), Extra::term()) -> 
			 {ok, NewCtx::record()}.

code_change(_OldVsn, Ctx, _Extra) ->
    {ok, Ctx}.


%%%===================================================================
%%% Internal functions
%%%===================================================================
full_filename(FileName) ->
    case filename:dirname(FileName) of
	"." when hd(FileName) =/= $. ->
	    filename:join(code:priv_dir(tellstick), FileName);
	_ -> 
	    FileName
    end.


subscribe(CoNode) ->
    ?dbg(?SERVER,"subscribe: IndexList = ~p",[?COMMANDS]),
    lists:foreach(fun({{Index, _SubInd}, _Type, _Value}) ->
			  co_api:extended_notify_subscribe(CoNode, Index)
		  end, ?COMMANDS).
unsubscribe(CoNode) ->
    ?dbg(?SERVER,"unsubscribe: IndexList = ~p",[?COMMANDS]),
    lists:foreach(fun({{Index, _SubInd}, _Type, _Value}) ->
			  co_api:extended_notify_unsubscribe(CoNode, Index)
		  end, ?COMMANDS).
    
take_item(Rid, Rchan, Items) ->
    take_item(Rid, Rchan, Items, []).

take_item(Rid, Rchan, [I=#item {rid=Rid,rchan=Rchan}|Is], Acc) ->
    {value,I,Is++Acc};
take_item(Rid, Rchan, [I|Is],Acc) ->
    take_item(Rid,Rchan,Is,[I|Acc]);
take_item(_Rid, _Rchan, [],_acc) ->
    false.


%% Load configuration file
load_config(File) ->
    case file:consult(File) of
	{ok, Cs} ->
	    load_conf(Cs,#conf{},[]);
	Error -> Error
    end.

load_conf([C | Cs], Conf, Items) ->
    case C of
	{Rid,Rchan,Type,Unit,Chan,Flags} ->
	    RCobId = translate(Rid),
	    Item = #item { rid=RCobId, rchan=Rchan, lchan=Rchan,
			   type=Type, unit=Unit, 
			   chan=Chan, flags=Flags,
			   active=false, level=0 },
	    load_conf(Cs, Conf, [Item | Items]);
	{product,Product1} ->
	    load_conf(Cs, Conf#conf { product=Product1}, Items);
	{device,Name} ->
	    load_conf(Cs, Conf#conf { device=Name}, Items);
	_ ->
	    {error, {unknown_config, C}}
    end;
load_conf([], Conf, Items) ->
    Dbg = get(dbg),
    if Dbg ->
	    io:format("Loaded configuration: \n ",[]),
	    lists:foreach(fun(Item) -> print_item(Item) end, Items);
       true ->
	    do_nothing
    end,
    if Conf#conf.product =:= undefined ->
	    {error, no_product};
       true ->
	    {ok, Conf#conf {items=Items}}
    end.
    


translate({xcobid, Func, Nid}) ->
    ?XCOB_ID(co_lib:encode_func(Func), Nid);
translate({cobid, Func, Nid}) ->
    ?COB_ID(co_lib:encode_func(Func), Nid).

power_on(Nid, ItemsToAdd) ->
    power_command(Nid, ?MSG_OUTPUT_ADD, ItemsToAdd).

power_off(Nid, ItemsToRemove) ->
    power_command(Nid, ?MSG_OUTPUT_DEL, ItemsToRemove).

power_command(Nid, Cmd, Items) ->
    lists:foreach(
      fun(I) ->
	      Value = ((I#item.rid bsl 8) bor I#item.rchan) band 16#ffffffff, %% ??
	      notify(Nid, pdo1_tx, Cmd, I#item.lchan, Value)
      end,
      Items).

reset_items(Items) ->
    lists:foreach(
      fun(I) ->
	      ?dbg(?SERVER,"reset_items: resetting ~p, ~.16#, ~.16#", 
		   [I#item.type,I#item.unit,I#item.chan]),
 	      call(I#item.type,[I#item.unit,I#item.chan,false])
      end,
      Items).

handle_notify({RemoteId, Index = ?MSG_POWER_ON, SubInd, Value}, Ctx) ->
    ?dbg(?SERVER,"handle_notify power on ~.16#: ID=~7.16.0#:~w, Value=~w", 
	      [RemoteId, Index, SubInd, Value]),
    remote_power_on(RemoteId, Ctx#ctx.node_id, Ctx#ctx.items),
    {noreply, Ctx};    
handle_notify({RemoteId, Index = ?MSG_POWER_OFF, SubInd, Value}, Ctx) ->
    ?dbg(?SERVER,"handle_notify power off ~.16#: ID=~7.16.0#:~w, Value=~w", 
	      [RemoteId, Index, SubInd, Value]),
    remote_power_off(RemoteId, Ctx#ctx.node_id, Ctx#ctx.items),
    {noreply, Ctx};    
handle_notify({RemoteId, Index, SubInd, Value}, Ctx) ->
    ?dbg(?SERVER,"handle_notify ~.16#: ID=~7.16.0#:~w, Value=~w", 
	      [RemoteId, Index, SubInd, Value]),
    case take_item(RemoteId, SubInd, Ctx#ctx.items) of
	false ->
	    ?dbg(?SERVER,"take_item = false", []),
	    lists:foreach(fun(Item) -> print_item(Item) end, Ctx#ctx.items),
	    {noreply,Ctx};
	{value,I,Is} ->
	    case Index of
		?MSG_DIGITAL ->
		    Items = digital_input(Ctx#ctx.node_id,I,Is,Value),
		    {noreply, Ctx#ctx { items=Items }};
		?MSG_ANALOG ->
		    Items = analog_input(Ctx#ctx.node_id,I,Is,Value),
		    {noreply, Ctx#ctx { items=Items }};
		?MSG_ENCODER ->
		    Items = encoder_input(Ctx#ctx.node_id,I,Is,Value),
		    {noreply, Ctx#ctx { items=Items }};
		_ ->
		    {noreply,Ctx}
	    end
    end.


remote_power_off(_Rid, _Nid, _Is) ->
    ok.

remote_power_on(Rid, Nid, [I | Is]) when I#item.rid =:= Rid ->
    %% add channel (local chan = remote chan)
    notify(Nid, pdo1_tx, ?MSG_OUTPUT_ADD, I#item.lchan,
	   ((Rid bsl 8) bor I#item.rchan) band 16#fffffff),
    %% update status
    AValue = if I#item.active -> 1; true -> 0 end,
    notify(Nid, pdo1_tx, ?MSG_OUTPUT_ACTIVE, I#item.lchan, AValue),
    %% if dimmer then send level
    Analog = proplists:get_bool(analog, I#item.flags),
    if Analog ->
	    notify(Nid, pdo1_tx, ?MSG_ANALOG, I#item.lchan, I#item.level);
       true ->
	    ok
    end,
    remote_power_on(Rid, Nid, Is);
remote_power_on(Rid, Nid, [_ | Is]) ->
    remote_power_on(Rid, Nid, Is);
remote_power_on(_Rid, _Nid, []) ->
    ok.



%%
%% Digital input
%%
digital_input(Nid, I, Is, Value) ->
    Digital    = proplists:get_bool(digital, I#item.flags),
    SpringBack = proplists:get_bool(springback, I#item.flags),
    if Digital, SpringBack, Value =:= 1 ->
	    Active = not I#item.active,
	    digital_input_call(Nid, I, Is, Active);
       Digital, not SpringBack ->
	    Active = Value =:= 1,
	    digital_input_call(Nid, I, Is, Active);
       Digital ->
	    ?dbg(?SERVER,"digital_input: No action.", []),
	    print_item(I),
	    [I | Is];
       true ->
	    ?dbg(?SERVER,"Not digital device.", []),
	    [I | Is]
    end.

digital_input_call(Nid, I, Is, Active) -> 
    ?dbg(?SERVER,"digital_input: calling driver.",[]),
    print_item(I),
    case call(I#item.type,[I#item.unit,I#item.chan,Active]) of
	ok ->
	    AValue = if Active -> 1; true -> 0 end,
	    notify(Nid, pdo1_tx, ?MSG_OUTPUT_ACTIVE, I#item.lchan, AValue),
	    [I#item { active=Active} | Is];
	_Error ->
	    [I | Is]
    end.

analog_input(Nid, I, Is, Value) ->
    Analog = proplists:get_bool(analog, I#item.flags),
    Min    = proplists:get_value(analog_min, I#item.flags, 0),
    Max    = proplists:get_value(analog_max, I#item.flags, 255),
    if Analog ->
	    %% Scale 0-65535 => Min-Max
	    IValue = trunc(Min + (Max-Min)*(Value/65535)),
	    %% scale Min-Max => 0-65535 (adjusting the slider)
	    RValue = trunc(65535*((IValue-Min)/(Max-Min))),
	    ?dbg(?SERVER,"analog_input: calling driver.",[]),
	    print_item(I),
	    case call(I#item.type,[I#item.unit,I#item.chan,IValue]) of
		ok ->
		    notify(Nid, pdo1_tx, ?MSG_ANALOG, I#item.lchan, RValue),
		    [I#item { level=RValue} | Is];
		_Error ->
		    [I | Is]
	    end;
       true ->
	    [I | Is]
    end.


notify(Nid, Func, Ix, Si, Value) ->
    co_api:notify(Nid, Func, Ix, Si,co_codec:encode(Value, unsigned32)).
    
encoder_input(_Nid, I, Is, _Value) ->
    ?dbg(?SERVER,"encoder_input: Not implemented yet.",[]),
    [I|Is].

call(Type, Args) ->	       
    ?dbg(?SERVER,"call: Type = ~p, Args = ~p.", [Type, Args]),
    try apply(tellstick_drv, Type, Args) of
	ok ->
	    ok;
	Error ->
	    ?dbg(?SERVER,"tellstick_drv: error=~p.", [Error]),
	    Error
    catch
	exit:Reason ->
	    ?dbg(?SERVER,"tellstick_drv: crash=~p.", [Reason]),
	    {error,Reason};
	error:Reason ->
	    ?dbg(?SERVER,"tellstick_drv: crash=~p.", [Reason]),
	    {error,Reason}
    end.
    
    
print_item(Item) ->
    io:format("Item = {Rid = ~.16#, Rchan = ~p, Lchan ~p, Type = ~p, Unit = ~p, Chan = ~p, Active = ~p, Level = ~p, Flags = ",
	      [Item#item.rid, Item#item.rchan, Item#item.lchan, Item#item.type,
	       Item#item.unit, Item#item.chan, Item#item.active, Item#item.level]),
    print_flags(Item#item.flags).

print_flags([]) ->
    io:format("}\n");
print_flags([Flag | Tail]) ->
    io:format("~p ",[Flag]),
    print_flags(Tail).
    
  
