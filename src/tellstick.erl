%%%-------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2010, Tony Rogvall
%%% @doc
%%%    Tellstick control application.
%%%    For detailed description of the functionality see the overview.
%%% @end
%%% Created :  5 Jul 2010 by Tony Rogvall <tony@rogvall.se>
%%%-------------------------------------------------------------------
-module(tellstick).

-behaviour(gen_server).

-include_lib("can/include/can.hrl").
-include_lib("canopen/include/canopen.hrl").
-include_lib("canopen/include/co_app.hrl").
-include_lib("canopen/include/co_debug.hrl").

%% API
-export([start_link/1, stop/0]).
-export([reload/0, reload/1]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

%% Testing
-export([start/0, debug/1, dump/0]).

-define(SERVER, ?MODULE). 
-define(COMMANDS,[{{?MSG_POWER_ON, 0}, ?INTEGER, 0},
		  {{?MSG_POWER_OFF, 0}, ?INTEGER, 0},
		  {{?MSG_DIGITAL, 0}, ?INTEGER, 0},
		  {{?MSG_ANALOG, 0}, ?INTEGER, 0},
		  {{?MSG_ENCODER, 0}, ?INTEGER, 0}]).


-record(conf,
	{
	  co_id,
	  product,
	  device,
	  items
	}).

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

-record(state,
	{
	  co_node, %% 
	  node_id, 
	  items    %% conf {ID,CHAN,TYPE,Command}
	}).

%%%===================================================================
%%% API
%%%===================================================================
%%--------------------------------------------------------------------
%% @spec start_link(Args) -> {ok, Pid} | ignore | {error, Error}
%%
%% @doc
%% Starts the server.
%% Loads configuration from File.
%%
%% @end
%%--------------------------------------------------------------------
start_link(Args) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Args, []).


%%--------------------------------------------------------------------
%% @spec stop() -> ok | {error, Error}
%%
%% @doc
%% Stops the server.
%%
%% @end
%%--------------------------------------------------------------------
stop() ->
    gen_server:call(?SERVER, stop).

%%--------------------------------------------------------------------
%% @spec reload() -> ok | {error, Error}
%%
%% @doc
%% Reloads the configuration file from default location.
%%
%% @end
%%--------------------------------------------------------------------
reload() ->
    File = filename:join(code:priv_dir(tellstick), "tellstick.conf"),
    gen_server:call(?SERVER, {reload, File}).

%%--------------------------------------------------------------------
%% @spec reload(File) -> ok | {error, Error}
%%
%% @doc
%% Reloads the configuration file.
%%
%% @end
%%--------------------------------------------------------------------
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
    start_link([{debug, true}]).
   

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init(Args) ->
    Dbg = proplists:get_value(debug, Args, false),
    put(dbg, Dbg),
    Simulated = proplists:get_value(simulated, Args, false),

    FileName = proplists:get_value(config, Args, "tellstick.conf"),
    ConfFile = filename:join(code:priv_dir(tellstick), FileName),
    io:format("~p: init: File=~p\n", [?MODULE,ConfFile]),
    case load_config(ConfFile) of
	{ok, Conf} ->
	    if Simulated ->
		    ?dbg(?SERVER,"init: Executing in simulated mode.\n",[]), 
		    {ok, _Pid} = tellstick_drv:start([{device,simulated},
						      {debug, get(dbg)}]);
		Conf#conf.device =:= undefined ->
		    ?dbg(?SERVER,"init: Driver undefined.\n", []),
		    {ok, _Pid} = tellstick_drv:start();
	       true ->
		    Device = Conf#conf.device,
		    ?dbg(?SERVER,"init: Device = ~p.\n", [Device]),
		    {ok, _Pid} = tellstick_drv:start([{device,Device},
						      {debug, get(dbg)}])
	    end,
	    {ok, _Dict} = co_node:attach(Conf#conf.co_id),
	    {xnodeid, ID} = co_node:get_option(Conf#conf.co_id, xnodeid),
	    Nid = ID bor ?COBID_ENTRY_EXTENDED,
	    subscribe(Conf#conf.co_id),
	    power_on(Nid, Conf#conf.items),
	    process_flag(trap_exit, true),
	    {ok, #state { co_node = Conf#conf.co_id, node_id = Nid, 
			  items=Conf#conf.items }};
	Error ->
	    ?dbg(?SERVER,"init: Not possible to load configuration file ~p.\n",
				 [ConfFile]),
	    {stop, Error}
    end.

%%--------------------------------------------------------------------
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @doc
%% Handling call messages.
%% Request can be the following:
%% <ul>
%% <li> {get, Index, SubInd} - Returns the value for Index:SubInd.</li>
%% <li> {set, Index, SubInd, Value} - Sets the value for Index:SubInd.</li>
%% <li> reload - Reloads the configuration file.</li>
%% <li> dump - Writes loop data to standard out (for debugging).</li>
%% <li> stop - Stops the application.</li>
%% </ul>
%%
%% @end
%%--------------------------------------------------------------------
handle_call({get, Index, SubInd}, _From, State) ->
    ?dbg(?SERVER,"get ~.16B:~.8B \n",[Index, SubInd]),
    {reply,{error, ?ABORT_NO_SUCH_OBJECT}, State};

handle_call({set, Index, SubInd, NewValue}, _From, State) ->
    ?dbg(?SERVER,"set ~.16B:~.8B to ~p\n",[Index, SubInd, NewValue]),
    {reply,{error, ?ABORT_NO_SUCH_OBJECT}, State};

handle_call({reload, File}, _From, State) ->
    case load_config(File) of
	{ok,Conf} ->
	    NewCoNode = Conf#conf.co_id,
	    {xnodeid, ID} = co_node:get_option(Conf#conf.co_id, xnodeid),
	    Nid = ID bor ?COBID_ENTRY_EXTENDED,
	    case State#state.co_node  of
		NewCoNode  ->
		    no_change;
		OldCoNode ->
		    unsubscribe(OldCoNode),
		    co_node:detach(OldCoNode),
		    co_node:attach(NewCoNode),
		    subscribe(NewCoNode)
	    end,
	    ItemsToAdd = lists:usort(Conf#conf.items) -- 
		lists:usort(State#state.items),
	    ItemsToRemove = lists:usort(State#state.items) -- 
		lists:usort(Conf#conf.items),
	    power_on(Nid, ItemsToAdd),
	    power_off(Nid, ItemsToRemove),
	    %% FIXME: handle changes 
	    {reply, ok, State#state { co_node = NewCoNode,
				      node_id = Nid,
				      items=Conf#conf.items}};
	Error ->
	    {reply, Error, State}
    end;
handle_call(dump, _From, State) ->
    io:format("State: CoNode = ~11.16.0#, ", [State#state.co_node]),
    io:format("NodeId = ~11.16.0#, Items=\n", [State#state.node_id]),
    lists:foreach(fun(Item) -> print_item(Item) end, State#state.items),
    {reply, ok, State};
handle_call({debug, TrueOrFalse}, _From, LoopData) ->
    put(dbg, TrueOrFalse),
    {reply, ok, LoopData};
handle_call(stop, _From, State) ->
    ?dbg(?SERVER,"stop:\n",[]),
    case whereis(list_to_atom(co_lib:serial_to_string(State#state.co_node))) of
	undefined -> 
	    do_nothing; %% Not possible to detach and unsubscribe
	_Pid ->
	    unsubscribe(State#state.co_node),
	    ?dbg(?SERVER,"stop: unsubscribed.\n",[]),
	    co_node:detach(State#state.co_node)
    end,
    ?dbg(?SERVER,"stop: detached.\n",[]),
    {stop, normal, ok, State};
handle_call(_Request, _From, State) ->
    {reply, {error,bad_call}, State}.

%%--------------------------------------------------------------------
%% @private
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @doc
%% Handling cast messages.
%%
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @doc
%% Handling all non call/cast messages.
%% 
%% @end
%%--------------------------------------------------------------------
handle_info({notify, RemoteId, Index = ?MSG_POWER_ON, SubInd, Value}, State) ->
    ?dbg(?SERVER,"handle_info: notify power on ~.16#: ID=~7.16.0#:~w, Value=~w \n", 
	      [RemoteId, Index, SubInd, Value]),
    remote_power_on(RemoteId, State#state.node_id, State#state.items),
    {noreply, State};    
handle_info({notify, RemoteId, Index = ?MSG_POWER_OFF, SubInd, Value}, State) ->
    ?dbg(?SERVER,"handle_info: notify power off ~.16#: ID=~7.16.0#:~w, Value=~w \n", 
	      [RemoteId, Index, SubInd, Value]),
    remote_power_off(RemoteId, State#state.node_id, State#state.items),
    {noreply, State};    
handle_info({notify, RemoteId, Index, SubInd, Value}, State) ->
    ?dbg(?SERVER,"handle_info: notify ~.16#: ID=~7.16.0#:~w, Value=~w \n", 
	      [RemoteId, Index, SubInd, Value]),
    case take_item(RemoteId, SubInd, State#state.items) of
	false ->
	    ?dbg(?SERVER,"take_item = false\n", []),
	    lists:foreach(fun(Item) -> print_item(Item) end, State#state.items),
	    {noreply,State};
	{value,I,Is} ->
	    case Index of
		?MSG_DIGITAL ->
		    Items = digital_input(State#state.node_id,I,Is,Value),
		    {noreply, State#state { items=Items }};
		?MSG_ANALOG ->
		    Items = analog_input(State#state.node_id,I,Is,Value),
		    {noreply, State#state { items=Items }};
		?MSG_ENCODER ->
		    Items = encoder_input(State#state.node_id,I,Is,Value),
		    {noreply, State#state { items=Items }};
		_ ->
		    {noreply,State}
	    end
    end;
handle_info({'EXIT', _Pid, co_node_terminated}, State) ->
    ?dbg(?SERVER,"handle_info: co_node terminated.\n",[]),
    {stop, co_node_terminated, ok, State};    
handle_info(Info, State) ->
    ?dbg(?SERVER,"handle_info: Unknown Info ~p\n", [Info]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(Reason, _State) ->
    ?dbg(?SERVER,"terminate: Reason = ~p\n",[Reason]),
    tellstick_drv:stop(),
    ?dbg(?SERVER,"terminate: driver stopped.\n",[]),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%%%===================================================================
%%% Internal functions
%%%===================================================================
subscribe(CoNode) ->
    lists:foreach(fun({{Index, _SubInd}, _Type, _Value}) ->
			  co_node:subscribe(CoNode, Index)
		  end, ?COMMANDS).
unsubscribe(CoNode) ->
    lists:foreach(fun({{Index, _SubInd}, _Type, _Value}) ->
			  co_node:unsubscribe(CoNode, Index)
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
	{co_id,CoId1} ->
	    load_conf(Cs, Conf#conf { co_id=CoId1}, Items);
	{product,Product1} ->
	    load_conf(Cs, Conf#conf { product=Product1}, Items);
	{device,Name} ->
	    load_conf(Cs, Conf#conf { device=Name}, Items);
	_ ->
	    {error, {unknown_config, C}}
    end;
load_conf([], Conf, Items) ->
    if Conf#conf.co_id =:= undefined ->
	    {error, no_co_id};
       Conf#conf.product =:= undefined ->
	    {ok, Conf#conf { product=(Conf#conf.co_id) band 16#ff,
			     items=Items}};
       true ->
	    {ok, Conf#conf {items=Items}}
    end.

translate({xcobid, Func, Nid}) ->
    ?XCOB_ID(co_file:func(Func), Nid);
translate({cobid, Func, Nid}) ->
    ?COB_ID(co_file:func(Func), Nid).

power_on(Nid, ItemsToAdd) ->
    power_command(Nid, ?MSG_OUTPUT_ADD, ItemsToAdd).

power_off(Nid, ItemsToRemove) ->
    power_command(Nid, ?MSG_OUTPUT_DEL, ItemsToRemove).

power_command(Nid, Cmd, Items) ->
    lists:foreach(
      fun(I) ->
	      co_node:notify(Nid, Cmd, I#item.lchan, 
			       ((I#item.rid bsl 8) bor I#item.rchan) 
				   band 16#ffffffff)
      end,
      Items).

remote_power_off(_Rid, _Nid, _Is) ->
    ok.

remote_power_on(Rid, Nid, [I | Is]) when I#item.rid =:= Rid ->
    %% add channel (local chan = remote chan)
    co_node:notify(Nid, ?MSG_OUTPUT_ADD, I#item.lchan,
		   ((Rid bsl 8) bor I#item.rchan) band 16#ffffffff),
    %% update status
    AValue = if I#item.active -> 1; true -> 0 end,
    co_node:notify(Nid, ?MSG_OUTPUT_ACTIVE, I#item.lchan, AValue),
    %% if dimmer then send level
    Analog = proplists:get_bool(analog, I#item.flags),
    if Analog ->
	    co_node:notify(Nid, ?MSG_ANALOG, I#item.lchan, I#item.level);
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
	    ?dbg(?SERVER,"digital_input: No action\n", []),
	    print_item(I),
	    [I | Is];
       true ->
	    ?dbg(?SERVER,"Not digital device\n", []),
	    [I | Is]
    end.

digital_input_call(Nid, I, Is, Active) -> 
    ?dbg(?SERVER,"digital_input: calling driver\n",[]),
    print_item(I),
    case call(I#item.type,[I#item.unit,I#item.chan,Active]) of
	ok ->
	    AValue = if Active -> 1; true -> 0 end,
	    co_node:notify(Nid, ?MSG_OUTPUT_ACTIVE, I#item.lchan, 
			   AValue),
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
	    ?dbg(?SERVER,"analog_input: calling driver\n",[]),
	    print_item(I),
	    case call(I#item.type,[I#item.unit,I#item.chan,IValue]) of
		ok ->
		    co_node:notify(Nid, ?MSG_ANALOG, I#item.lchan, RValue),
		    [I#item { level=RValue} | Is];
		_Error ->
		    [I | Is]
	    end;
       true ->
	    [I | Is]
    end.


encoder_input(_Nid, I, Is, _Value) ->
    ?dbg(?SERVER,"encoder_input: Not implemented yet\n",[]),
    [I|Is].

call(Type, Args) ->	       
    ?dbg(?SERVER,"call: Type = ~p, Args = ~p\n", [Type, Args]),
    try apply(tellstick_drv, Type, Args) of
	ok ->
	    ok;
	Error ->
	    ?dbg(?SERVER,"tellstick_drv: error=~p\n", [Error]),
	    Error
    catch
	exit:Reason ->
	    ?dbg(?SERVER,"tellstick_drv: crash=~p\n", [Reason]),
	    {error,Reason};
	error:Reason ->
	    ?dbg(?SERVER,"tellstick_drv: crash=~p\n", [Reason]),
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
    
  
