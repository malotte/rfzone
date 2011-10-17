%%%-------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2010, Tony Rogvall
%%% @doc
%%%    Tellstick control application
%%% @end
%%% Created :  5 Jul 2010 by Tony Rogvall <tony@rogvall.se>
%%%-------------------------------------------------------------------
-module(tellstick).

-behaviour(gen_server).

-include_lib("can/include/can.hrl").
-include_lib("../include/pds_proto.hrl").
%% API
-export([start/0]).
-export([reload/0]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

%% pds_node callbacks
-export([pds_get/4,
	 pds_set/4,
	 pds_notify/5,
	 pds_state/5]).
	 
-define(SERVER, ?MODULE). 

-record(conf,
	{
	  serial,
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
	  pds,   %% pds state (MUST BE AT THIS LOCATION)
	  items  %% conf {ID,CHAN,TYPE,Command}
	}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start() ->
%%    pds_mgr:start(), %% start multicast + pds_mgr
    can_udp:start(),  %% listen to multicast interface
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

reload() ->
    gen_server:call(?SERVER, reload).

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
init([]) ->
    case load_config() of
	{ok, Conf} ->
	    Nid = ?CAN_EFF_FLAG bor (Conf#conf.serial bsr 8),
	    Pds = pds_node:new(Nid, Conf#conf.serial, Conf#conf.product),
	    if Conf#conf.device =:= undefined ->
		    tellstick_drv:start();
	       true ->
		    tellstick_drv:start([{device,Conf#conf.device}])
	    end,
	    can_router:attach(),
	    power_on(Nid, Conf),
	    {ok, #state { pds=Pds, items=Conf#conf.items }};
	Error ->
	    {stop, Error}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(reload, _From, State) ->
    case load_config() of
	{ok,Conf} ->
	    Nid = ?CAN_EFF_FLAG bor (Conf#conf.serial bsr 8),
	    Pds = State#state.pds,
	    Pds1 = Pds#pds_state { nid = Nid, 
				   serial=Conf#conf.serial, 
				   product=Conf#conf.product },
	    power_on(Nid, Conf),
	    %% FIXME: handle changes 
	    {reply, ok, State#state { pds=Pds1, 
				      items=Conf#conf.items}};
	Error ->
	    {reply, Error, State}
    end;
handle_call(_Request, _From, State) ->
    {reply, {error,bad_call}, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(Frame, State) when is_record(Frame, can_frame) ->
    io:format("handle_info: FRAME = ~p\n", [Frame]),
    pds_node:dispatch(Frame, ?MODULE, State);
handle_info(Info, State) ->
    io:format("handle_info: Unknown Info ~p\n", [Info]),
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
terminate(_Reason, _State) ->
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
%%% PDS callbacks
%%%===================================================================
pds_get(_Ix,_Si,_Data,St) ->
    {reply,{error, index}, St}.

pds_set(_Ix,_Si,_Data,St) ->
    {reply,{error, index}, St}.

pds_notify(Rid,?MSG_POWER_ON,_Si,_Value,St) ->
    io:format("power_on: ID=~8.16.0B\n", [Rid]),
    Nid = (St#state.pds)#pds_state.nid,
    remote_power_on(Rid, Nid, St#state.items),
    {noreply, St};    
pds_notify(Rid,?MSG_POWER_OFF,_Si,_Value,St) ->
    io:format("power_off: ID=~8.16.0B\n", [Rid]),
    Nid = (St#state.pds)#pds_state.nid,
    remote_power_off(Rid, Nid, St#state.items),
    {noreply, St};
pds_notify(Rid,Ix,Si,Value,St) ->
    io:format("~.16B: ID=~8.16.0B:~w, Value=~w \n", [Ix, Rid, Si, Value]),
    case take_item(Rid,Si,St#state.items) of
	false ->
	    io:format("tellstick: take_item = false, Items = ~p\n", [St#state.items]),
	    {noreply,St};
	{value,I,Is} ->
	    case Ix of
		?MSG_DIGITAL ->
		    Nid = (St#state.pds)#pds_state.nid,
		    Items = digital_input(Nid,I,Is,Value),
		    io:format("digital: Items= ~p\n", [Items]),
		    {noreply, St#state { items=Items}};
		?MSG_ANALOG ->
		    Nid = (St#state.pds)#pds_state.nid,
		    Items = analog_input(Nid,I,Is,Value),
		    io:format("analog: Items= ~p\n", [Items]),
		    {noreply, St#state { items=Items}};
		?MSG_ENCODER ->
		    Nid = (St#state.pds)#pds_state.nid,
		    Items = encoder_input(Nid,I,Is,Value),
		    io:format("encoder: Items= ~p\n", [Items]),
		    {noreply, St#state { items=Items}};
		_ ->
		    {noreply,St}
	    end
    end.


pds_state(_Channel,_Active,_Alarm,_Ack,St) ->
    {noreply,St}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
take_item(Rid, Rchan, Items) ->
    take_item(Rid, Rchan, Items, []).

take_item(Rid, Rchan, [I=#item {rid=Rid,rchan=Rchan}|Is], Acc) ->
    {value,I,Is++Acc};
take_item(Rid, Rchan, [I|Is],Acc) ->
    take_item(Rid,Rchan,Is,[I|Acc]);
take_item(_Rid, _Rchan, [],_acc) ->
    false.


%% Load configuration file
load_config() ->
    File = filename:join(code:priv_dir(pds), "tellstick.conf"),
    case file:consult(File) of
	{ok, Cs} ->
	    load_conf(Cs,#conf{},[]);
	Error -> Error
    end.

load_conf([C | Cs], Conf, Items) ->
    case C of
	{Rid,Rchan,Type,Unit,Chan,Flags} ->
	    Item = #item { rid=Rid, rchan=Rchan, lchan=Rchan,
			   type=Type, unit=Unit, 
			   chan=Chan, flags=Flags,
			   active=false, level=0 },
	    load_conf(Cs, Conf, [Item | Items]);
	{serial,Serial1} ->
	    load_conf(Cs, Conf#conf { serial=Serial1}, Items);
	{product,Product1} ->
	    load_conf(Cs, Conf#conf { product=Product1}, Items);
	{device,Name} ->
	    load_conf(Cs, Conf#conf { device=Name}, Items);
	_ ->
	    {error, {unknown_config, C}}
    end;
load_conf([], Conf, Items) ->
    if Conf#conf.serial =:= undefined ->
	    {error, no_serial};
       Conf#conf.product =:= undefined ->
	    {ok, Conf#conf { product=(Conf#conf.serial) band 16#ff,
			     items=Items}};
       true ->
	    {ok, Conf#conf {items=Items}}
    end.

power_on(Nid, Conf) ->
    lists:foreach(fun(I) ->
			  pds_proto:notify(Nid, ?MSG_OUTPUT_ADD, I#item.lchan, 
					   ((I#item.rid bsl 8) bor I#item.rchan) 
					       band 16#ffffffff)
		  end,
    Conf#conf.items).

remote_power_off(_Rid, _Nid, _Is) ->
    ok.

remote_power_on(Rid, Nid, [I | Is]) when I#item.rid =:= Rid ->
    %% add channel (local chan = remote chan)
    pds_proto:notify(Nid, ?MSG_OUTPUT_ADD, I#item.lchan,
		   ((Rid bsl 8) bor I#item.rchan) band 16#ffffffff),
    %% update status
    AValue = if I#item.active -> 1; true -> 0 end,
    pds_proto:notify(Nid, ?MSG_OUTPUT_ACTIVE, I#item.lchan, AValue),
    %% if dimmer then send level
    Analog = proplists:get_bool(analog, I#item.flags),
    if Analog ->
	    pds_proto:notify(Nid, ?MSG_ANALOG, I#item.lchan, I#item.level);
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
	    case call(I#item.type,[I#item.unit,I#item.chan,Active]) of
		ok ->
		    AValue = if Active -> 1; true -> 0 end,
		    pds_proto:notify(Nid, ?MSG_OUTPUT_ACTIVE, I#item.lchan, 
				     AValue),
		    [I#item { active=Active} | Is];
		_Error ->
		    [I | Is]
	    end;
       Digital, not SpringBack ->
	    Active = Value =:= 1,
	    case call(I#item.type, [I#item.unit,I#item.chan,Active]) of
		ok ->
		    AValue = if Active -> 1; true -> 0 end,
		    pds_proto:notify(Nid, ?MSG_OUTPUT_ACTIVE, I#item.lchan, 
				     AValue),
		    [I#item { active=Active} | Is];
		_Error ->
		    [I | Is]
	    end;
       Digital ->
	    [I | Is];
       true ->
	    io:format("Not digital device\n"),
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
	    case call(I#item.type,[I#item.unit,I#item.chan,IValue]) of
		ok ->
		    pds_proto:notify(Nid, ?MSG_ANALOG, I#item.lchan, RValue),
		    [I#item { level=RValue} | Is];
		_Error ->
		    [I | Is]
	    end;
       true ->
	    [I | Is]
    end.


encoder_input(_Nid, I, Is, _Value) ->
    io:format("Not implemented yet\n"),
    [I|Is].

call(Type, Args) ->	       
    io:format("call: Type = ~p, Args = ~p\n", [Type, Args]),
    try apply(tellstick_drv, Type, Args) of
	ok ->
	    ok;
	Error ->
	    io:format("tellstick_drv: error=~p\n", [Error]),
	    Error
    catch
	exit:Reason ->
	    io:format("tellstick_drv: crash=~p\n", [Reason]),
	    {error,Reason};
	error:Reason ->
	    io:format("tellstick_drv: crash=~p\n", [Reason]),
	    {error,Reason}
    end.
    
    
