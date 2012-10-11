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
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @author Malotte Westman Lönne <malotte@malotte.net>
%%% @copyright (C) 2012, Tony Rogvall
%%% @doc
%%%    rfZone control server.
%%%    For detailed description of the functionality see the overview.
%%%
%%% Created:  5 Jul 2010 by Tony Rogvall 
%%% @end
%%%-------------------------------------------------------------------
-module(rfzone_srv).

-behaviour(gen_server).

-include_lib("can/include/can.hrl").
-include_lib("canopen/include/canopen.hrl").
-include_lib("canopen/include/co_app.hrl").

-include_lib("lager/include/log.hrl").

%% API
-export([start_link/1, 
	 stop/0]).
-export([reload/0, 
	 reload/1]).
%% RPC API
-export([analog_input/3,digital_input/3]).
-export([item_configuration/2, configure_item/3]).
-export([device_configuration/0, configure_device/1]).
-export([action/4]).
-export([power/2]).

%% gen_server callbacks
-export([init/1, 
	 handle_call/3, 
	 handle_cast/2, 
	 handle_info/2,
	 terminate/2, 
	 code_change/3]).

%% Testing
-export([debug/1, 
	 dump/0]).

-define(SERVER, ?MODULE). 

%% CANopen indexes
-define(COMMANDS,[{{?MSG_POWER_ON, 0}, ?INTEGER, 0},
		  {{?MSG_POWER_OFF, 0}, ?INTEGER, 0},
		  {{?MSG_DIGITAL, 0}, ?INTEGER, 0},
		  {{?MSG_ANALOG, 0}, ?INTEGER, 0},
		  {{?MSG_ENCODER, 0}, ?INTEGER, 0}]).

%% Default rfzone version
-define(DEF_VERSION, v1).

%% rfZone configuration from file
-record(conf,
	{
	  product,
	  device = {simulated, ?DEF_VERSION},
	  items = [],
	  events = []
	}).

%% Controlled item
-record(item,
	{
	  %% Remote ID
	  rid,    %% remote id
	  rchan,  %% remote channel

	  %% Local ID
	  type,     %% nexa, ikea ... email
	  unit,     %% serial/unit/house code
	  lchan,    %% Local channel / mail content
	  flags=[], %% Control flags  / mail flags

	  %% State
	  active = false,  %% off
	  inhibit,         %% filter activation events
	  level = 0,       %% dim level
	  timer            %% To filter analog input
	}).

-record(event,
	{
	  event,
	  rid,    %% EFID|SFID
	  rchan,  %% 1..254
	  type,   %% digital,analog,encoder
	  value   %% depend on type
	}).

%% Loop data
-record(ctx,
	{
	  co_node, %% any identity of co_node i.e. serial | name | nodeid ...
	  node_id, %% nodeid | xnodeid of co_node, needed in notify
	           %% should maybe be fetched when needed instead of stored in loop data ??
	  device,  %% device used
	  items,   %% controlled items
	  events,  %% controlled events
	  trace
	}).

%% For dialyzer
-type start_options()::{co_node, CoNode::node_identity()} |
		       {config, File::string()} |
		       {reset, TrueOrFalse::boolean()} |
		       {retry_timeout, TimeOut::timeout()} |
%%		       {simulated, TrueOrFalse::boolean()} |
		       {linked, TrueOrFalse::boolean()} |
		       {debug, TrueOrFalse::boolean()}.

%%%===================================================================
%%% API
%%%===================================================================
%%--------------------------------------------------------------------
%% @doc
%% Starts the server.
%% Loads configuration from File.
%% @end
%%--------------------------------------------------------------------
-spec start_link(Opts::list(start_options())) -> 
			{ok, Pid::pid()} | 
			ignore | 
			{error, Error::term()}.

start_link(Opts) ->
    lager:info("~p: start_link: args = ~p\n", [?MODULE, Opts]),
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
%% Returns an items configuration
%% @end
%%--------------------------------------------------------------------
-spec item_configuration(RemoteId::integer(),
			 Channel::integer()) -> 
				{ok, Item::list(tuple())} | 
				{error, Error::term()}.

item_configuration(RemoteId, Channel) 
  when is_integer(RemoteId) andalso
       is_integer(Channel)  ->
    gen_server:call(?SERVER, {item_configuration, RemoteId, Channel}).

%%--------------------------------------------------------------------
%% @doc
%% Adds/Updates an item configuration
%% @end
%%--------------------------------------------------------------------
-spec configure_item(RemoteId::tuple(),
		     Channel::tuple(),
		     list(tuple())) -> 
			    ok | 
			    {error, Error::term()}.

configure_item({'remote-id', RidList}, {'remote-channel', Channel}, Config) 
  when is_list(RidList) andalso is_integer(Channel) ->
    case remote_id(RidList, undefined) of
	error ->
	    {error, illegal_remote_id};
	RemoteId ->
	    gen_server:call(?SERVER, {configure_item, RemoteId, Channel, Config})
    end.
	    
remote_id([], RemoteId) -> 
    RemoteId;
remote_id([{'type-of-cobid', xcobid} | Rest], RemoteId) -> 
    remote_id(Rest, RemoteId); 
remote_id([{'function-code', pdo1_tx} | Rest], RemoteId) -> 
    remote_id(Rest, RemoteId);
remote_id([{'remote-node-id', RemoteId} | Rest], undefined) 
  when is_integer(RemoteId) -> 
    remote_id(Rest, RemoteId);
remote_id(_Other, _RemoteId) -> 
    error.

%%--------------------------------------------------------------------
%% @doc
%% Returns the device configuration
%% @end
%%--------------------------------------------------------------------
-spec device_configuration() -> 
				  {ok, Item::list(tuple())} | 
				  {error, Error::term()}.

device_configuration() ->
    gen_server:call(?SERVER, device_configuration).

%%--------------------------------------------------------------------
%% @doc
%% Sets the device configuration
%% @end
%%--------------------------------------------------------------------
-spec configure_device(Config::list(tuple())) -> 
			      ok | 
			      {error, Error::term()}.

configure_device(Config) when is_list(Config) ->
    case proplists:get_value('tellstick-device', Config) of
	undefined ->
	    {error, no_device_given};
	DevName when is_list(DevName) orelse DevName == simulated -> 
	    case proplists:get_value(version, Config, v1) of
		Version when Version == v1 orelse Version == v2 ->
		    gen_server:call(?SERVER, {configure_device, {DevName, Version}});
		_Illegal ->
		    {error, illegal_version}
	    end
    end.
%%--------------------------------------------------------------------
%% @doc
%% Executes the equivalance of an ?MSG_ANALOG
%% @end
%%--------------------------------------------------------------------
-spec analog_input(RemoteId::integer(),
		   Channel::integer(),
		   Level::integer()) -> ok | {error, Error::term()}.

analog_input(RemoteId, Channel, Level) 
  when is_integer(RemoteId) andalso
       is_integer(Channel) andalso
       is_integer(Level) ->
    gen_server:cast(?SERVER, {analog_input, RemoteId, Channel, Level}).

%%--------------------------------------------------------------------
%% @doc
%% Executes the equivalance of an ?MSG_DIGTAL
%% @end
%%--------------------------------------------------------------------
-spec digital_input(RemoteId::integer(),
		    Channel::integer(),
		    Action::on | off) -> ok | {error, Error::term()}.

digital_input(RemoteId, Channel, Action) 
  when is_integer(RemoteId) andalso
       is_integer(Channel) andalso
       (Action == on orelse Action == off) ->
    gen_server:cast(?SERVER, {digital_input, RemoteId, Channel, 
			      if Action == on -> 1; Action == off -> 0 end});
digital_input(RemoteId, Channel, Action) 
  when is_integer(RemoteId) andalso
       is_integer(Channel) andalso
       Action == onoff -> %% Springback
    gen_server:cast(?SERVER, {digital_input, RemoteId, Channel, 1}).

%%--------------------------------------------------------------------
%% @doc
%% Executes the equivalance of an extended notify message.
%% @end
%%--------------------------------------------------------------------
-spec action(RemoteId::integer(),
	     Action::digital | analog | encoder,
	     Channel::integer(),
	     Value::integer() | on | off) -> ok | {error, Error::term()}.

action(RemoteId, Action, Channel, Value) 
  when is_integer(RemoteId) andalso
       is_integer(Channel) andalso
       (Value == on orelse Value == off) andalso
       Action == digital  ->
    gen_server:cast(?SERVER, {action, RemoteId, encode(Action), Channel, 
			      if Value == on -> 1; Value == off -> 0 end});
action(RemoteId, Action, Channel, Value) 
  when is_integer(RemoteId) andalso
       is_integer(Channel) andalso
       is_integer(Value) andalso
       (Action == analog orelse Action == encoder) ->
    gen_server:cast(?SERVER, {action, RemoteId, encode(Action), Channel, Value}).

%%--------------------------------------------------------------------
%% @doc
%% Executes the equivalance of an extended notify message.
%% @end
%%--------------------------------------------------------------------
-spec power(RemoteId::integer(), Value:: on | off) -> ok | {error, Error::term()}.

power(RemoteId, Value)
  when is_integer(RemoteId) andalso
       (Value == on orelse Value == off) ->
    gen_server:cast(?SERVER, {power, RemoteId, encode(Value)}).
    
%%--------------------------------------------------------------------
%% @doc
%% Reloads the default configuration file (rfzone.conf) from the 
%% default location (the applications priv-dir).
%% @end
%%--------------------------------------------------------------------
-spec reload() -> ok | {error, Error::term()}.

reload() ->
    File = filename:join(code:priv_dir(rfzone), "rfzone.conf"),
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
-spec init(Args::list(start_options())) -> 
		  {ok, Ctx::#ctx{}} |
		  {stop, Reason::term()}.

init(Args) ->
    lager:info("~p: init: args = ~p,\n pid = ~p\n", [?MODULE, Args, self()]),
    case proplists:get_value(co_node, Args) of
	undefined ->
	    lager:debug("init: No CANOpen node given.", []),
	    {stop, no_co_node};
	CoNode = {name, _Name} ->
	    conf(Args, CoNode);
	CoId ->
	    CoNode = {name, _Name} = co_api:get_option(CoId, name),
	    conf(Args, CoNode)
    end.

conf(Args,CoNode) ->
    FileName = proplists:get_value(config, Args, "rfzone.conf"),
    ConfFile =  full_filename(FileName),
    {ok,Trace} = set_trace(proplists:get_value(debug, Args, false), undefined),

    lager:debug("init: File = ~p", [ConfFile]),

    case load_config(ConfFile) of
	{ok, Conf=#conf {device = Device}} ->
	    start_device(Args, Device),
	    tellstick_drv:subscribe(),
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
			device = Device,
			node_id = Nid, 
			items=Conf#conf.items,
			events=Conf#conf.events,
			trace=Trace
		      }};
	Error ->
	    lager:debug(
		 "init: Not possible to load configuration file ~p.",
		 [ConfFile]),
	    {stop, Error}
    end.

start_device(Args, Device) ->
    %% Debug flag is inherited by tellstick_drv
    Debug = proplists:get_value(debug, Args, false),
    case Device of
	{simulated, _Version} ->
	    lager:debug("start_device: running simulated.",[]),
	    %% How handle ??
	    Args1 = [{device,{simulated, ?DEF_VERSION}},
		     {debug, Debug}],
	    lager:debug("start_device: args=~p.", [Args1]),
	    {ok, _Pid} = tellstick_drv:start_link(Args1);
	Device ->
	    TOut = proplists:get_value(retry_timeout, Args, infinity),
	    Args1 = [{device,Device},
		     {retry_timeout, TOut},
		     {debug,Debug}],
	    lager:debug("start_device: args=~p.", [Args1]),
	    {ok, _Pid} = tellstick_drv:start_link(Args1)
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

-spec handle_call(Request::call_request(), From::{pid(), Tag::term()}, Ctx::#ctx{}) ->
			 {reply, Reply::term(), Ctx::#ctx{}} |
			 {noreply, Ctx::#ctx{}} |
			 {stop, Reason::atom(), Reply::term(), Ctx::#ctx{}}.


handle_call({reload, File}, _From, 
	    Ctx=#ctx {node_id = Nid, device = OldDevice, items = OldItems}) ->
    lager:debug("reload ~p",[File]),
    ConfFile = full_filename(File),
    case load_config(ConfFile) of
	{ok,_Conf=#conf {device=NewDevice,items=NewItems,events=Events}} ->
	    if NewDevice =/= OldDevice ->
		    tellstick_drv:change_device(NewDevice);
	       true ->
		    do_nothing
	    end,
		    
	    NewItemIds = 
		lists:foldl(
		  fun(_Item=#item {rid = Rid, rchan = Rchan}, Ids) ->
			  [{Rid, Rchan} | Ids]
		  end, [], NewItems),
	    OldItemIds = 
		lists:foldl(
		  fun(_Item=#item {rid = Rid, rchan = Rchan}, Ids) ->
			  [{Rid, Rchan} | Ids]
		  end, [], OldItems),

	    ItemIdsToAdd = lists:usort(NewItemIds) -- lists:usort(OldItemIds),
	    ItemIdsToRemove = lists:usort(OldItemIds) -- lists:usort(NewItemIds),

	    lager:debug("\nold items = ~p\n new items ~p\n "
		 "items to add ~p\n items to remove ~p\n",
		 [OldItemIds, NewItemIds, ItemIdsToAdd, ItemIdsToRemove]),

	    ItemsToAdd = 
		lists:foldl(
		  fun(Item=#item {rid = Rid, rchan = Rchan}, Items) ->
			  case lists:member({Rid, Rchan}, ItemIdsToAdd) of
			      true -> [ Item | Items ];
			      false -> Items
			  end
		  end, [], NewItems),
	    ItemsToRemove = 
		lists:foldl(
		  fun(Item=#item {rid = Rid, rchan = Rchan}, Items) ->
			  case lists:member({Rid, Rchan}, ItemIdsToRemove) of
			      true -> [ Item | Items ];
			      false -> Items
			  end
		  end, [], OldItems),

	    power_on(Nid, ItemsToAdd),
	    power_off(Nid, ItemsToRemove),
	    {reply, ok, Ctx#ctx {items = NewItems, events=Events,
				 device = NewDevice}};
	Error ->
	    {reply, Error, Ctx}
    end;

handle_call({item_configuration, RemoteId, Channel} = _X, _From, 
	    Ctx=#ctx {items = Items}) ->
    lager:debug("handle_call: received item_configuration req ~p.",[_X]),
    case take_item(RemoteId, Channel, Items) of
	false ->
	    {reply, {error, no_such_item}, Ctx};
	{value,Item,_OtherItems} ->
	    {reply, {ok, format(Item)}, Ctx}
    end;

handle_call({configure_item, RemoteId, Channel, Config} = _X, _From, 
	    Ctx=#ctx {items = Items}) ->
    lager:debug("handle_call: received configure_item req ~p.",[_X]),
    case take_item(RemoteId, Channel, Items) of
	false ->
	    NewItem = item(Config, #item {rid = RemoteId, rchan = Channel}),
	    case verify_item(NewItem) of
		ok ->
		    {reply, ok, Ctx=#ctx {items = [NewItem | Items]}};
		{error, Reason} ->
		    {reply, {error, Reason}, Ctx}
	    end;
	{value,OldItem,OtherItems} ->
	    NewItem = item(Config, OldItem),
	    {reply, ok, Ctx#ctx {items = [NewItem | OtherItems]}}
    end;

handle_call(device_configuration, _From, 
	    Ctx=#ctx {device = Device}) ->
    lager:debug("handle_call: received device_configuration req.",[]),
    {reply, {ok, format(Device)}, Ctx};

handle_call({configure_device, NewDevice} = _X, _From, 
	    Ctx=#ctx {device = OldDevice}) ->
    lager:debug("handle_call: received configure_device req ~p.",[_X]),
    if NewDevice =/= OldDevice ->
	    tellstick_drv:change_device(NewDevice);
       true ->
	    do_nothing
    end,
    {reply, ok, Ctx#ctx {device = NewDevice}};

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

handle_call(dump, _From, 
	    Ctx=#ctx {co_node = CoNode, device = Device, 
		      node_id = {Type,Nid}, 
		      events = Events,
		      items = Items}) ->
    io:format("Ctx: CoNode = ~p, Device = ~p,", [CoNode, Device]),
    io:format("NodeId = {~p, ~.16#}, Items=\n", [Type, Nid]),
    lists:foreach(fun(Item) -> print_item(Item) end, Items),
    lists:foreach(fun(Evt) -> print_event(Evt) end, Events),
    {reply, ok, Ctx};

handle_call({debug, On}, _From, Ctx) ->
    case set_trace(On, Ctx#ctx.trace) of
	{ok,Trace} ->
	    {reply, ok, Ctx#ctx { trace = Trace }};
	Error ->
	    {reply, Error, Ctx}
    end;
handle_call(stop, _From, Ctx) ->
    lager:debug("stop:",[]),
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
-type cast_msg()::
	{extended_notify, Index::integer(), Frame::#can_frame{}} |
	term().

-spec handle_cast(Msg::cast_msg(), Ctx::#ctx{}) -> 
			 {noreply, Ctx::#ctx{}} |
			 {stop, Reason::term(), Ctx::#ctx{}}.

handle_cast({extended_notify, _Index, Frame}, Ctx) ->
    lager:debug("handle_cast: received notify with frame ~w.",[Frame]),
    %% Check index ??
    RemoteId = ?CANID_TO_COBID(Frame#can_frame.id), %% Not X format ??
    <<_F:1, _Addr:7, Ix:16/little, Si:8, Data:4/binary>> = Frame#can_frame.data,
    lager:debug("handle_cast: index = ~.16.0#:~w, data = ~w.",[Ix, Si, Data]),
    try co_codec:decode(Data, unsigned32) of
	{Value, _Rest} ->
	    handle_notify({RemoteId, Ix, Si, Value}, Ctx)
    catch
	error:_Reason ->
	    lager:debug("handle_cast: decode failed, reason ~p.",[_Reason]),
	    {noreply, Ctx}
    end;

handle_cast({analog_input, RemoteId, Channel, Value} = _X, Ctx) ->
    lager:debug("handle_cast: received analog_input ~p.",[_X]),
    handle_notify({RemoteId, ?MSG_ANALOG, Channel, Value}, Ctx);

handle_cast({digital_input, RemoteId, Channel, Value} = _X, Ctx) ->
    lager:debug("handle_cast: received digital_input ~p.",[_X]),
    handle_notify({RemoteId, ?MSG_DIGITAL, Channel, Value}, Ctx);

handle_cast({action, RemoteId, Action, Channel, Value} = _X, Ctx) ->
    lager:debug("handle_cast: received action ~p.",[_X]),
    handle_notify({RemoteId, Action, Channel, Value}, Ctx);

handle_cast({power, RemoteId, ?MSG_POWER_ON} = _X, Ctx) ->
    lager:debug("handle_cast: received power on ~p.",[_X]),
    remote_power_on(RemoteId, Ctx#ctx.node_id, Ctx#ctx.items),
    {noreply, Ctx};    

handle_cast({power, RemoteId, ?MSG_POWER_OFF} = _X, Ctx) ->
    lager:debug("handle_cast: received power off ~p.",[_X]),
    remote_power_off(RemoteId, Ctx#ctx.node_id, Ctx#ctx.items),
    {noreply, Ctx};    

handle_cast({name_change, OldName, NewName}, 
	    Ctx=#ctx {co_node = {name, OldName}}) ->
   lager:debug( "handle_cast: co_node name change from ~p to ~p.", 
	 [OldName, NewName]),
    {noreply, Ctx#ctx {co_node = {name, NewName}}};

handle_cast({name_change, _OldName, _NewName}, Ctx) ->
   lager:debug( "handle_cast: co_node name change from ~p to ~p, ignored.", 
	 [_OldName, _NewName]),
    {noreply, Ctx};

handle_cast({nodeid_change, _TypeOfNid, _OldNid, _NewNid}, 
	    Ctx=#ctx {co_node = CoNode}) ->
   lager:debug( "handle_cast: co_node nodied ~p change from ~p to ~p.", 
	[_TypeOfNid, _OldNid, _NewNid]),
    Nid = co_api:get_option(CoNode, id),
    {noreply, Ctx#ctx {node_id = {name, Nid}}};

handle_cast(_Msg, Ctx) ->
    lager:debug("handle_cast: Unknown Msg ~p", [_Msg]),
    {noreply, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages.
%% 
%% @end
%%--------------------------------------------------------------------
-type info()::
	{analog_input, Rid::integer(), Rchan::term(), Value::integer()} |
	{'EXIT', Pid::pid(), co_node_terminated} |
	term().

-spec handle_info(Info::info(), Ctx::#ctx{}) -> 
			 {noreply, Ctx::#ctx{}} |
			 {noreply, Ctx::#ctx{}, Timeout::timeout()} |
			 {stop, Reason::term(), Ctx::#ctx{}}.

handle_info({analog_input, Rid, Rchan, Value}, 
	    Ctx=#ctx {node_id = Nid, items = OldItems}) ->
    %% Buffered analog input
    lager:debug("handle_info: analog_input.",[]),
    case take_item(Rid, Rchan, OldItems) of
	false ->
	    lager:debug("handle_info: analog_input, item ~p, ~p not found", 
		 [Rid, Rchan]),
	    {noreply,Ctx};
	{value,Item,OtherItems} ->
	    lager:debug("analog_input: received buffered call for ~.16#, ~p, ~p.",
		 [Rid, Rchan, Value]),
	    NewItems = exec_analog_input(Item,Nid,OtherItems,Value),
	    {noreply, Ctx#ctx { items = NewItems }}
    end;

handle_info({tellstick_event,_Ref,EventData}, Ctx) ->
    lager:debug("handle_info: event ~p\n.",[EventData]),
    case take_event(EventData, Ctx#ctx.events) of
	false ->
	    lager:debug("handle_info: tellstick_event, event ~p not found", 
		 [EventData]),
	    {noreply,Ctx};
	E ->
	    Data = <<(E#event.value):32/little>>,
	    case E#event.type of
		digital ->
		    co_api:notify(E#event.rid, ?MSG_DIGITAL,
				  E#event.rchan, Data),
		    {noreply,Ctx};
%%		    handle_notify(E#event.rid, ?MSG_DIGITAL,
%%				  E#event.rchan, E#event.value);
		analog ->
		    co_api:notify(E#event.rid, ?MSG_ANALOG,
				  E#event.rchan, Data),
		    {noreply,Ctx};
%%		    handle_notify(E#event.rid, ?MSG_ANALOG,
%%				  E#event.rchan, E#event.value);
		encoder ->
		    co_api:notify(E#event.rid, ?MSG_ENCODER,
				  E#event.rchan, Data),
		    {noreply,Ctx}
%%		    handle_notify(E#event.rid, ?MSG_ENCODER,
%%				  E#event.rchan, E#event.value)
	    end
    end;
handle_info({timeout,Ref,inhibit}, Ctx) ->
    %% inhibit period is overl unlock item
    case lists:keytake(Ref, #item.inhibit, Ctx#ctx.items) of
	{value,I,Is} ->
	    Ctx1 = Ctx#ctx { items = [I#item {inhibit=undefined} | Is]},
	    {noreply, Ctx1};
	false ->
	    {noreply, Ctx}
    end;

handle_info({'EXIT', _Pid, co_node_terminated}, Ctx) ->
    lager:debug("handle_info: co_node terminated.",[]),
    {stop, co_node_terminated, Ctx};   
 
handle_info(_Info, Ctx) ->
    lager:debug("handle_info: Unknown Info ~p", [_Info]),
    {noreply, Ctx}.

%%--------------------------------------------------------------------
%% @private
%%--------------------------------------------------------------------
-spec terminate(Reason::term(), Ctx::#ctx{}) -> 
		       no_return().

terminate(_Reason, Ctx=#ctx {co_node = CoNode}) ->
    lager:debug("terminate: Reason = ~p",[_Reason]),
    case co_api:alive(CoNode) of
	true ->
	    unsubscribe(CoNode),
	    lager:debug("terminate: unsubscribed.",[]),
	    co_api:detach(CoNode);
	false -> 
	    do_nothing %% Not possible to detach and unsubscribe
    end,
    lager:debug("terminate: detached.",[]),
    tellstick_drv:stop(),
    lager:debug("terminate: driver stopped.",[]),
    stop_trace(Ctx#ctx.trace),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process ctx when code is changed
%%
%% @end
%%--------------------------------------------------------------------
-spec code_change(OldVsn::term(), Ctx::#ctx{}, Extra::term()) -> 
			 {ok, NewCtx::#ctx{}}.

code_change(_OldVsn, Ctx, _Extra) ->
    {ok, Ctx}.


%%%===================================================================
%%% Internal functions
%%%===================================================================

stop_trace(undefined) ->
    undefined;
stop_trace(Trace) ->
    lager:stop_trace(Trace),
    undefined.

%% enable/disable module debug trace
set_trace(false, Trace) ->
    Trace1 = stop_trace(Trace),
    lager:set_loglevel(lager_console_backend, info),
    {ok,Trace1};
set_trace(true, undefined) ->
    lager:trace_console([{module,?MODULE}], debug);
set_trace(true, Trace) -> 
    {ok,Trace}.


full_filename(FileName) ->
    case filename:dirname(FileName) of
	"." when hd(FileName) =/= $. ->
	    filename:join(code:priv_dir(rfzone), FileName);
	_ -> 
	    FileName
    end.

subscribe(CoNode) ->
    lager:debug("subscribe: IndexList = ~w",[?COMMANDS]),
    lists:foreach(fun({{Index, _SubInd}, _Type, _Value}) ->
			  co_api:extended_notify_subscribe(CoNode, Index)
		  end, ?COMMANDS).
unsubscribe(CoNode) ->
    lager:debug("unsubscribe: IndexList = ~w",[?COMMANDS]),
    lists:foreach(fun({{Index, _SubInd}, _Type, _Value}) ->
			  co_api:extended_notify_unsubscribe(CoNode, Index)
		  end, ?COMMANDS).
    
take_item(Rid, Rchan, Items) ->
    take_item(Rid, Rchan, Items, []).

take_item(Rid, Rchan, [I=#item {rid=Rid,rchan=Rchan}|Is], Acc) ->
    {value,I,Is++Acc};
take_item(Rid, Rchan, [I|Is],Acc) ->
    take_item(Rid,Rchan,Is,[I|Acc]);
take_item(_Rid, _Rchan, [],_Acc) ->
    false.


take_event(Event, [E=#event { event=Pattern }|Ts]) ->
    case match_event(Pattern, Event) of
	true -> E;
	false -> take_event(Event, Ts)
    end;
take_event(_Event, []) ->
    false.

match_event([{K,V}|Kvs], Event) ->
    case lists:keytake(K, 1, Event) of
	{value,{K,V},Event1} -> match_event(Kvs,Event1);
	_ -> false
    end;
match_event([], _Event) ->
    true.
	    


%% Load configuration file
load_config(File) ->
    case file:consult(File) of
	{ok, Cs} ->
	    load_conf(Cs,#conf{},[],[]);
	Error -> Error
    end.

load_conf([C | Cs], Conf, Is, Ts) ->
    case C of
	{Rid,Rchan,Type,Unit,Chan,Flags} ->
	    RCobId = translate(Rid),
	    Item = #item { rid=RCobId, rchan=Rchan, 
			   type=Type, unit=Unit, 
			   lchan=Chan, flags=Flags,
			   active=false, level=0 },
	    case verify_item(Item) of
		ok ->
		    load_conf(Cs, Conf, [Item | Is], Ts);
		{error, Reason} ->
		    lager:error(
		      "Inconsistent item ~p, could not be loaded, reason ~p\n", 
		      [Item, Reason]),
		    load_conf(Cs, Conf, Is, Ts)
	    end;
	{event, Event, {Rid,RChan,Type,Value}} ->
	    RCobId = translate(Rid),
	    Item = #event { event = Event,
			    rid   = RCobId,
			    rchan = RChan,
			    type  = Type,
			    value = Value },
	    case verify_event(Item) of
		ok ->
		    load_conf(Cs, Conf, Is, [Item | Ts]);
		{error, Reason} ->
		    lager:error(
		      "Inconsistent item ~p, could not be loaded, reason ~p\n", 
		      [Item, Reason]),
		    load_conf(Cs, Conf, Is,Ts)
	    end;
	{product,Product1} ->
	    load_conf(Cs, Conf#conf { product=Product1}, Is, Ts);
	{device,Name,Version} ->
	    load_conf(Cs, Conf#conf { device={Name, Version}}, Is, Ts);
	{device,Name} ->
	    %% Use default version
	    load_conf(Cs, Conf#conf { device={Name, ?DEF_VERSION}}, Is, Ts);
	_ ->
	    {error, {unknown_config, C}}
    end;
load_conf([], Conf, Is, Ts) ->
    lager:debug("Loaded configuration: \n ",[]),
    lists:foreach(fun(I) -> lager:debug("~s", [fmt_item(I)]) end, Is),
    lists:foreach(fun(E) -> lager:debug("~s", [fmt_event(E)]) end, Ts),
    if Conf#conf.product =:= undefined ->
	    {error, no_product};
       true ->
	    {ok, Conf#conf {items=Is,events=Ts}}
    end.

verify_item(_I=#item {type = email, unit = _Unit, lchan = Email, flags = Opts}) ->
    case verify_mail(Email) of
	ok -> 
	    verify_mail_options(Opts);
	Error -> Error
    end;    

verify_item(_I=#item {type = Type, unit = Unit, lchan = Channel, flags = Flags}) ->
    case verify_unit_range(Type, Unit) of
	ok ->
	    case verify_channel_range(Type, Channel) of
		ok ->
		    Analog = proplists:get_bool(analog, Flags),
		    Digital = proplists:get_bool(digital, Flags),
		    if Analog orelse Digital ->
			    verify_flags(Type, Flags);
		       true ->
			    {error, must_be_digital_or_analog}
		    end;
		{error, _Reason} = N->
		    N
	    end;
	{error, _Reason} = N ->
	    N
    end.

verify_event(_I=#event {event=Event, 
			rid   = _RCobId,
			rchan = RChan,
			type  = Type,
			value = Value }) ->
    verify_all(
      [fun() -> (RChan >= 1) andalso (RChan =< 254) end,
       {error,bad_channel_number},

       fun() -> case Type of
		    analog -> true;
		    digital -> true;
		    encoder -> true;
		    _ -> false
		end
       end, {error, bad_channel_type},

       fun() -> case Type of
		    analog when Value >= 0, Value =< 16#ffff ->
			true;
		    digital when Value =:= 0; Value =:= 1 ->
			true;
		    encoder -> is_integer(Value);
		    _ -> false
		end
       end, {error, bad_value_range},

       fun() -> verify_event(Event, [protocol,model,data]) end,
       {error, bad_event}

      ]).

verify_mail({From,To,Headers,Body}) ->
    L = lists:flatten(
	  [ [fun() -> verify_addr(From) end, {error,bad_from_addr}],
	    [ [ fun() -> verify_addr(T) end, {error,bad_from_addr} ] ||
		T <- To ],
	    [fun() -> try iolist_size([Headers,Body]) of
			  _ -> true
		      catch
			  error:_ ->
			       false
		      end
	     end, {error, bad_mail_body}]]),
    verify_all(L).

%% form <name@host.com>
%%       name@host.com
verify_addr(Name) when is_binary(Name) ->
    verify_addr(binary_to_list(Name));
verify_addr([$<|Addr1]) ->
    case lists:reverse(Addr1) of
	[$>|Addr2] -> verify_addr(lists:reverse(Addr2));
	_ -> false
    end;
verify_addr(Addr) when is_list(Addr) ->
    case string:tokens(Addr, "@") of
	[_Name, Host] ->
	    case inet_parse:domain(Host) of
		true ->
		    case inet_parse:dots(Host) of
			{N,false} when N > 0 ->
			    true;
			_ -> false
		    end;
		false ->
		    false
	    end;
	_ -> false
    end;
verify_addr(_) ->
    false.

verify_mail_options([{K,_V}|Opts]) ->
    case K of
	inhibit -> verify_mail_options(Opts);
	relay    -> verify_mail_options(Opts);
	auth     -> verify_mail_options(Opts);
	username -> verify_mail_options(Opts);
	password -> verify_mail_options(Opts);
	no_mx_lookups -> verify_mail_options(Opts);
	retries -> verify_mail_options(Opts);
	tls -> verify_mail_options(Opts);
	ssl -> verify_mail_options(Opts);
	port -> verify_mail_options(Opts);
	_ -> {error, {unknown_option, K}}
    end;
verify_mail_options([K|Opts]) ->
    case K of
	digital    -> verify_mail_options(Opts);
	springback -> verify_mail_options(Opts);
	_ ->  {error, {unknown_option, K}}
    end;
verify_mail_options([]) ->
    ok.
	
	    

verify_all([Fun, Error | More]) ->
    try Fun() of
	true -> verify_all(More);
	false -> Error
    catch
	error:_ -> Error
    end;
verify_all([]) ->
    ok.

verify_event(Event, [K|Ks]) ->
    Event1 = lists:keydelete(K, 1, Event),
    verify_event(Event1, Ks);
verify_event([], _) ->
    true;
verify_event(_, []) ->
    false.


verify_unit_range(nexa, Unit) 
  when Unit >= $A,
       Unit =< $P ->
    ok;
verify_unit_range(nexax, Unit) 
  when Unit >= 0,
       Unit =< 16#3fffffff ->
    ok;
verify_unit_range(waveman, Unit) 
  when Unit >= $A,
       Unit =< $P ->
    ok;
verify_unit_range(sartano, _Unit) ->
    ok;
verify_unit_range(ikea, Unit) 
  when Unit >= 1,
       Unit =< 16 ->
    ok;
verify_unit_range(risingsun, Unit) 
  when Unit >= 1,
       Unit =< 4 ->
    ok;
verify_unit_range(_Type, _Unit) ->
    lager:debug("verify_unit_range: invalid type/unit combination ~p,~p", 
		   [_Type, _Unit]),
    {error, invalid_type_unit_combination}.

verify_channel_range(nexa, Channel) 
  when Channel >= 1,
       Channel =< 16 ->
    ok;
verify_channel_range(nexax, Channel) 
  when Channel >= 1,
       Channel =< 16 ->
    ok;
verify_channel_range(waveman, Channel) 
  when Channel >= 1,
       Channel =< 16 ->
    ok;
verify_channel_range(sartano, Channel)
  when Channel >= 1,
       Channel =< 16#3ff ->
   ok;
verify_channel_range(ikea, Channel)
  when Channel >= 1,
       Channel =< 10 ->
    ok;
verify_channel_range(risingsun, Channel)
  when Channel >= 1,
       Channel =< 4 ->
    ok;
verify_channel_range(_Type, _Channel) ->
    lager:debug("verify_channel_range: invalid type/channel combination ~p,~p", 
		   [_Type, _Channel]),
    {error, invalid_type_channel_combination}.


verify_flags(_Type, []) ->
    ok;
verify_flags(Type, [digital | Flags]) 
  when Type == nexa;
       Type == nexax;
       Type == waveman;
       Type == sartano;
       Type == ikea;
       Type == risingsun ->
    verify_flags(Type, Flags);
verify_flags(Type, [springback | Flags]) 
  when Type == nexa;
       Type == waveman;
       Type == sartano;
       Type == risingsun ->
    verify_flags(Type, Flags);
verify_flags(Type, [analog | Flags]) 
  when Type == nexax;
       Type == ikea ->
    verify_flags(Type, Flags);
verify_flags(ikea = Type, [{analog_min, Min} | Flags]) 
  when Min >= 0, Min =< 10 ->
    verify_flags(Type, Flags);
verify_flags(ikea = Type, [{analog_max, Max} | Flags]) 
  when Max >= 0, Max =< 10 ->
    verify_flags(Type, Flags);
verify_flags(ikea = Type, [{style, Style} | Flags]) 
  when Style == smooth;
       Style == instant ->
    verify_flags(Type, Flags);
verify_flags(nexax = Type, [{analog_min, Min} | Flags]) 
  when Min >= 0, Min =< 255 ->
    verify_flags(Type, Flags);
verify_flags(nexax = Type, [{analog_max, Max} | Flags]) 
  when Max >= 0, Max =< 255 ->
    verify_flags(Type, Flags);
verify_flags(Type, [{inhib,Time} | Flags])
  when is_integer(Time), Time >= 0 ->
    verify_flags(Type, Flags);
verify_flags(_Type, [_Flag | _Flags]) ->
    lager:debug("verify_flags: invalid type/flag combination ~p,~p", 
		   [_Type, _Flag]),
    {error, invalid_type_flag_combination}.

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
	      notify(Nid, pdo1_tx, Cmd, I#item.rchan, Value)
      end,
      Items).

reset_items(Items) ->
    lists:foreach(
      fun(I) ->
	      lager:debug("reset_items: resetting ~p, ~p, ~p", 
		   [I#item.type,I#item.unit,I#item.lchan]),
	      %% timer:sleep(1000), %% Otherwise rfzone chokes ..
	      Fs = I#item.flags,
	      Analog = proplists:get_bool(analog, Fs),
	      Digital = proplists:get_bool(digital, Fs),
	      if Digital ->
		      run(I#item.type,[I#item.unit,I#item.lchan,false,[],Fs]);
		 Analog ->
		      run(I#item.type,[I#item.unit,I#item.lchan,0,
				       [{style, instant}], Fs])
	      end
      end,
      Items).

handle_notify({RemoteId, _Index = ?MSG_POWER_ON, _SubInd, _Value}, Ctx) ->
    lager:debug("handle_notify power on ~.16#: ID=~7.16.0#:~w, Value=~w", 
	      [RemoteId, _Index, _SubInd, _Value]),
    remote_power_on(RemoteId, Ctx#ctx.node_id, Ctx#ctx.items),
    {noreply, Ctx};    
handle_notify({RemoteId, _Index = ?MSG_POWER_OFF, _SubInd, _Value}, Ctx) ->
    lager:debug("handle_notify power off ~.16#: ID=~7.16.0#:~w, Value=~w", 
	      [RemoteId, _Index, _SubInd, _Value]),
    remote_power_off(RemoteId, Ctx#ctx.node_id, Ctx#ctx.items),
    {noreply, Ctx};    
handle_notify({RemoteId, Index, SubInd, Value}, Ctx) ->
    lager:debug("handle_notify ~.16#: ID=~7.16.0#:~w, Value=~w", 
	      [RemoteId, Index, SubInd, Value]),
    case take_item(RemoteId, SubInd, Ctx#ctx.items) of
	false ->
	    lager:debug("take_item = false", []),
	    {noreply,Ctx};
	{value,I,Is} ->
	    case Index of
		?MSG_DIGITAL ->
		    Items = digital_input_int(I,Ctx#ctx.node_id,Is,Value),
		    {noreply, Ctx#ctx { items=Items }};
		?MSG_ANALOG ->
		    Items = analog_input_int(I,Is,Value),
		    {noreply, Ctx#ctx { items=Items }};
		?MSG_ENCODER ->
		    Items = encoder_input_int(I,Ctx#ctx.node_id,Is,Value),
		    {noreply, Ctx#ctx { items=Items }};
		_ ->
		    {noreply,Ctx}
	    end
    end.


remote_power_off(_Rid, _Nid, _Is) ->
    ok.

remote_power_on(Rid, Nid, [I | Is]) when I#item.rid =:= Rid ->
    %% add channel (local chan = remote chan)
    notify(Nid, pdo1_tx, ?MSG_OUTPUT_ADD, I#item.rchan,
	   ((Rid bsl 8) bor I#item.rchan) band 16#fffffff),
    %% update status
    AValue = if I#item.active -> 1; true -> 0 end,
    notify(Nid, pdo1_tx, ?MSG_OUTPUT_ACTIVE, I#item.rchan, AValue),
    %% if dimmer then send level
    Analog = proplists:get_bool(analog, I#item.flags),
    if Analog ->
	    notify(Nid, pdo1_tx, ?MSG_ANALOG, I#item.rchan, I#item.level);
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
digital_input_int(I, Nid, Is, Value) ->
    Digital    = proplists:get_bool(digital, I#item.flags),
    SpringBack = proplists:get_bool(springback, I#item.flags),
    if Digital, SpringBack, Value =:= 1 ->
	    Active = not I#item.active,
	    digital_input_call(I, Nid, Is, Active);
       Digital, not SpringBack ->
	    Active = Value =:= 1,
	    if I#item.active =:= Active ->  %% no change, do noting
		    [I | Is];
	       true ->
		    digital_input_call(I, Nid, Is, Active)
	    end;
       Digital ->
	    lager:debug("digital_input_int: No action.", []),
	    lager:debug("item = ~s\n", [fmt_item(I)]),
	    [I | Is];
       true ->
	    lager:debug("digital_input_int: not digital item.", []),
	    [I | Is]
    end.

digital_input_call(I, _Nid, Is, true) when I#item.inhibit =/= undefined ->
    [I|Is];   %% not allowed to turn on yet
digital_input_call(I, Nid, Is, Active) -> 
    lager:debug("digital_input: calling driver.",[]),
    lager:debug("item = ~s\n", [fmt_item(I)]),
    case run(I#item.type,[I#item.unit,I#item.lchan,Active,[],I#item.flags]) of
	ok ->
	    AValue = if Active -> 1; true -> 0 end,
	    notify(Nid, pdo1_tx, ?MSG_OUTPUT_ACTIVE, I#item.rchan, AValue),
	    case proplists:get_value(inhibit, I#item.flags, 0) of
		0 ->
		    [I#item { active=Active} | Is];
		T ->
		    TRef = erlang:start_timer(T, self(), inhibit),
		    [I#item { active=Active, inhibit=TRef} | Is]
	    end;
	_Error ->
	    [I | Is]
    end.

analog_input_int(I=#item {rid = Rid, rchan = Rchan, timer = Timer, flags = Flags}, 
	     Is, Value) ->
    Analog = proplists:get_bool(analog, Flags),
    if Analog ->
	    stop_timer(Timer),
	    lager:debug("analog_input_int: buffer call for ~.16#, ~p, ~p.",
		 [Rid, Rchan, Value]),
	    Tref = 
		erlang:send_after(100, self(), {analog_input, Rid, Rchan, Value}),
	    [I#item {timer = Tref} | Is];
       true ->
	    lager:debug("analog_input_int: not analog item ~p, ~p, ignored.",
		 [Rid, Rchan]),
	    [I | Is]
    end.

exec_analog_input(I=#item {type = Type, rchan = Rchan, flags = Flags, 
			   unit = Unit, lchan = Dchan, active = Active}, 
		  Nid, Is, Value) ->
    lager:debug("exec_analog_input: updating item:.",[]),
    lager:debug("item = ~s\n", [fmt_item(I)]),

    Digital = proplists:get_bool(digital, Flags),
    Min     = proplists:get_value(analog_min, Flags, 0),
    Max     = proplists:get_value(analog_max, Flags, 255),
    Style   = proplists:get_value(style, Flags, smooth),
    %% Calculate actual level
    %% Scale 0-65535 => Min-Max
    IValue = trunc(Min + (Max-Min)*(Value/65535)),
    %% scale Min-Max => 0-65535 (adjusting the slider)
    RValue = trunc(65535*((IValue-Min)/(Max-Min))),

    lager:debug("analog_input: calling driver with new value ~p",[IValue]),
    case run(Type,[Unit,Dchan,IValue,[{style, Style}],Flags]) of
	ok ->
	    %% For devices without digital control output_active
	    %% is sent when level is changed from/to 0
	    case {Digital,RValue == 0,Active} of 
		{false, false, false} ->
		    %% Slider "turned on"
		    notify(Nid, pdo1_tx, ?MSG_OUTPUT_ACTIVE,Rchan, 1);
		{false, true, true} ->
		    %% Slider "turned off"
		    notify(Nid, pdo1_tx, ?MSG_OUTPUT_ACTIVE,Rchan, 0);
		_Any ->
		    do_nothing
	    end,
	    notify(Nid, pdo1_tx, ?MSG_OUTPUT_VALUE,Rchan, RValue),
	    NewI = I#item {level=RValue, timer = undefined, 
			    active = ((RValue =/= 0) andalso not Digital)}, 
	    [NewI | Is];
	_Error ->
	    [I | Is]
    end.

notify(Nid, Func, Ix, Si, Value) ->
    co_api:notify_from(Nid, Func, Ix, Si,co_codec:encode(Value, unsigned32)).
    
encoder_input_int(_Nid, I, Is, _Value) ->
    lager:debug("encoder_input_int: Not implemented yet.",[]),
    [I|Is].

run(email,[_Unit,{_From,_To,_Headers,_Body},false,_Style,_Flags]) ->
    ok;  %% do not send
run(email,[_Unit,{From,To,Headers,Body},true,_Style,Flags]) ->
    %% protect from sending more than one time per ...
    %% fixme: setup callback and log failed attempts
    Flags1 = Flags -- [digital,springback],
    Headers1 = 
	[ [H,"\r\n"] || 
	    H <- Headers ++ 
		[["Date: ", smtp_util:rfc5322_timestamp()],
		 ["Message-ID:", smtp_util:generate_message_id()]]],
    Message = [Headers1,"\r\n",Body],
    case gen_smtp_client:send({From, To, Message}, Flags1) of
	{ok,_Pid} ->
	    ok;
	Error -> Error
    end;
run(Type, [Unit,Chan,Active,Style,_Flags]) ->
    Args = [Unit,Chan,Active,Style],
    lager:debug("action: Type = ~p, Args = ~w.", [Type, Args]),
    try apply(tellstick_drv, Type, Args) of
	ok ->
	    ok;
	Error ->
	    lager:debug("tellstick_drv: error=~p.", [Error]),
	    Error
    catch
	exit:Reason ->
	    lager:debug("tellstick_drv: crash=~p.", [Reason]),
	    {error,Reason};
	error:Reason ->
	    lager:debug("tellstick_drv: crash=~p.", [Reason]),
	    {error,Reason}
    end.


fmt_item(I) when is_record(I,item) ->
    io_lib:format("{rid:~.16#,rchan:~p,type:~p,unit:~p,chan:~p,"
		  "active:~p,level:~p,flags=~s}",
		  [I#item.rid, I#item.rchan, 
		   I#item.type,I #item.unit, I#item.lchan, 
		   I#item.active, I#item.level,
		   fmt_flags(I#item.flags)]).

fmt_event(E) when is_record(E, event) ->
    io_lib:format("{~p,rid:~.16#,rchan:~w,type:~w,value:~w}", 
		  [E#event.event,E#event.rid,E#event.rchan, E#event.type,
		   E#event.value]).
    
print_item(I) when is_record(I,item) ->
    io:format("item: ~s\n", [fmt_item(I)]).

print_event(E) when is_record(E, event) ->
    io:format("event: ~s\n", [fmt_event(E)]).

fmt_flags([Flag|Tail]) ->
    [io_lib:format("~p ", [Flag]) | fmt_flags(Tail)];
fmt_flags([]) -> "".

  
encode(on) -> ?MSG_POWER_ON;
encode(off) -> ?MSG_POWER_OFF;
encode(digital) -> ?MSG_DIGITAL;
encode(analog) -> ?MSG_ANALOG;
encode(encoder) -> ?MSG_ENCODER.
     
item([], Item) ->
    Item;
item([{'remote-id', _Channel} | Rest], Item) ->
    %% Already stored
    item(Rest, Item);
item([{'remote-channel', _Channel} | Rest], Item) ->
    %% Already stored
    item(Rest, Item);
item([{protocol, Type} | Rest], Item) ->
    item(Rest, Item#item {type = Type});
item([{unit, Unit} | Rest], Item) ->
    item(Rest, Item#item {unit = Unit});
item([{channel, DevChannel} | Rest], Item) ->
    item(Rest, Item#item {lchan = DevChannel});
item([{flags, Flags} | Rest], Item) ->
    case flags(Flags, []) of
	error ->
	    error;
	F ->
	    item(Rest, Item#item {flags = F})
    end;
item(_Other,_Item) ->
    error.

flags([], Flags) ->
    Flags;
flags([{Flag, true} | Rest], Flags) ->
    flags(Rest, [Flag | Flags]);
flags([{_Flag, false} | Rest], Flags) ->
    flags(Rest, Flags);
flags([{_Key, _Value} = Flag | Rest], Flags) ->
    flags(Rest, [Flag | Flags]);
flags(_Other, _Flags) ->
    error.

format({simulated, _Version}) ->
    [{'tellstick-device', simulated}];
format({Device, Version}) ->
    [{'tellstick-device', Device}, {version, Version}];
format(_I=#item{rid = RemoteId, rchan = RChannel, active = Active, type = Type,
		unit = Unit, lchan = DeviceChannel, flags = Flags, level = Level}) ->
    Common = [{'remote-id', 
	       [{'type-of-cobid', xcobid},
		{'function-code',pdo1_tx},
		{'remote-node-id', RemoteId}]},
	      {'remote-channel', RChannel},
	      {state, if Active == true -> on; Active == false -> off end},
	      {protocol, Type},
	      {channel, DeviceChannel},
	      {flags, format(Flags,[])}],
    DevChan = if Type == sartano -> []; true -> [{unit, Unit}] end,
    Lev = case lists:member(analog, Flags) of
	      false -> [];
	      true -> [{level, Level}]
	  end,
    Common ++ DevChan ++ Lev.
format([], Acc) -> Acc;
format([{_Key, _Value} = Flag | Rest], Acc) -> 
    format(Rest, [Flag | Acc]);
format([Key | Rest], Acc) -> 
    format(Rest, [{Key, true} | Acc]).
		      
stop_timer(undefined) ->
    undefined;
stop_timer(Ref) ->
    erlang:cancel_timer(Ref).


    
