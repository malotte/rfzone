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
%%% @copyright (C) 2013, Tony Rogvall
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
-include("rfzone.hrl").

%% API
-export([start_link/1, 
	 stop/0]).
-export([reload/0, 
	 reload/1]).
%% RPC API
-export([analog_output/3,
	 digital_output/3]).
-export([item_configuration/2, 
	 configure_item/3]).
-export([device_configuration/0, 
	 configure_device/1]).
-export([action/4]).
-export([power/2]).

%% gen_server callbacks
-export([init/1, 
	 handle_call/3, 
	 handle_cast/2, 
	 handle_info/2,
	 terminate/2, 
	 code_change/3]).

%% Execution process
-export([execute_mfa/4]).

%% testing
-export([dump/0]).
-export([rid_translate/1]).

-define(SERVER, ?MODULE). 

%% CANopen indexes
-define(COMMANDS,[{{?MSG_POWER_ON, 0}, ?INTEGER, 0},
		  {{?MSG_POWER_OFF, 0}, ?INTEGER, 0},
		  {{?MSG_DIGITAL, 0}, ?INTEGER, 0},
		  {{?MSG_ANALOG, 0}, ?INTEGER, 0},
		  {{?MSG_ENCODER, 0}, ?INTEGER, 0}]).

%% Default rfzone version
-define(DEF_VERSION, v1).

%% The cpu pin for access to piface board
-define(PIFACE_PIN, 25).

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
	  level = 0,       %% dim level

	  inhibit,         %% filter activation events
	  timer            %% To filter analog input
	}).

-record(event,
	{
	  pattern,  
	  ref,    %% reference to extern event subscription when used
	  rid,    %% EFID|SFID
	  rchan,  %% 1..254
	  type,   %% digital,analog,encoder
	  value,  %% depend on type
	  edge = undefined, %% Interrupt direction
	  polarity = false %% Switch polarity of value
	}).

-record(apply_item,
	{
	  pid::pid(),  
	  timer::timeout(),
	  output::term()
	}).

%% Loop data
-record(ctx,
	{
	  co_node::term(), %% any identity of co_node i.e. 
	                   %% serial | name | nodeid ...
	  node_id::integer(), %% nodeid | xnodeid of co_node, needed in notify
	                      %% should maybe be fetched when needed instead 
	                      %% of stored in loop data ??
	  device = {simulated, ?DEF_VERSION}::tuple(),
	  retry_timeout = infinity::timeout(),
	  items = []::list(),   %% controlled items
	  events = []::list(),  %% controlled events
	  apps = []::list(atom()),  %% apps to verify loaded
	  apply_list = []::list(#apply_item{}), %% outstanding apply request
	  file = ""::string(),  %% full name of conf file loaded	  
	  piface_initialized = false::boolean(), %% flag needed for gpio/piface
	  piface_mask = 16#ff::integer() %% Values for piface pins
	}).

%% For dialyzer
-type start_options()::{co_node, CoNode::node_identity()} |
		       {config, File::string()} |
		       {reset, TrueOrFalse::boolean()} |
		       {retry_timeout, TimeOut::timeout()} |
%%		       {simulated, TrueOrFalse::boolean()} |
		       {linked, TrueOrFalse::boolean()}.

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

%% @private
%% Pick out remote id	    
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
-spec analog_output(RemoteId::integer(),
		   Channel::integer(),
		   Level::integer()) -> ok | {error, Error::term()}.

analog_output(RemoteId, Channel, Level) 
  when is_integer(RemoteId) andalso
       is_integer(Channel) andalso
       is_integer(Level) ->
    gen_server:cast(?SERVER, {analog_output, RemoteId, Channel, Level}).

%%--------------------------------------------------------------------
%% @doc
%% Executes the equivalance of an ?MSG_DIGTAL
%% @end
%%--------------------------------------------------------------------
-spec digital_output(RemoteId::integer(),
		    Channel::integer(),
		    Action::on | off | integer()) -> 
			    ok | {error, Error::term()}.

digital_output(RemoteId, Channel, Action) 
  when is_integer(RemoteId) andalso
       is_integer(Channel) andalso
       (Action =:= on orelse Action =:= off) ->
    gen_server:cast(?SERVER, {digital_output, RemoteId, Channel, 
			      if Action =:= on -> 1; Action =:= off -> 0 end});
digital_output(RemoteId, Channel, Action) 
  when is_integer(RemoteId) andalso
       is_integer(Channel) andalso
       Action =:= onoff -> %% Springback
    gen_server:cast(?SERVER, {digital_output, RemoteId, Channel, 1});
digital_output(RemoteId, Channel, Action) 
  when is_integer(RemoteId) andalso
       is_integer(Channel) andalso
       (Action =:= 0 orelse Action =:= 1) -> 
    gen_server:cast(?SERVER, {digital_output, RemoteId, Channel, Action});
digital_output(RemoteId, Channel, BinAction) 
  when is_integer(RemoteId) andalso
       is_integer(Channel) andalso
       is_binary(BinAction) -> 
    %% Fix for enum from exodm !!!!!
    Action = case BinAction of
		 <<"on">> -> 1;
		 <<"off">> -> 0
	     end,
    gen_server:cast(?SERVER, {digital_output, RemoteId, Channel, Action}).

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
    gen_server:cast(?SERVER, 
		    {action, RemoteId, encode(Action), Channel, Value}).

%%--------------------------------------------------------------------
%% @doc
%% Executes the equivalance of an extended notify message.
%% @end
%%--------------------------------------------------------------------
-spec power(RemoteId::integer(), Value:: on | off) -> 
		   ok | {error, Error::term()}.

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
-spec reload(File::string()) -> 
		    ok | {error, Error::term()}.

reload(File) ->
    gen_server:call(?SERVER, {reload, File}).

%% Test functions
%% @private
dump() ->
    gen_server:call(?SERVER, dump).

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

    %% if on_host is true no io-pins are accessible
    case application:get_env(rfzone, on_host) of
	{ok, true} ->
	    ?dbg("Running on host", []),
	    put(on_host, true);
	_NotTrue ->
	    ?dbg("Running on device", []),
	    put(on_host, false)
    end,
    
    %% CANOpen node mandatory
    case proplists:get_value(co_node, Args) of
	undefined ->
	    ?dbg("init: No CANOpen node given.", []),
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
    TOut = proplists:get_value(retry_timeout, Args, infinity),

    ?dbg("init: File = ~p", [ConfFile]),

    case load_config(ConfFile) of
	{ok, _Conf=#conf {device = Device, items = Items, events = Events}} ->
	    start_device(Device, [{retry_timeout, TOut}]),
	    tellstick_drv:subscribe(),
	    {ok, _Dict} = co_api:attach(CoNode),
	    Nid = co_api:get_option(CoNode, id),
	    subscribe(CoNode),
	    case proplists:get_value(reset, Args, false) of
		true -> reset_items(Items);
		false -> do_nothing
	    end,
	    power_on(Nid, Items),
	    {PifaceInit,Events1} = init_events(Events, [], false),
	    process_flag(trap_exit, true),
	    {ok, #ctx { co_node = CoNode, 
			device = Device,
			retry_timeout = TOut,
			node_id = Nid, 
			items=Items,
			events=Events1,
			file=ConfFile,
			piface_initialized = PifaceInit
		      }};
	Error ->
	    ?dbg("init: Not possible to load configuration file ~p.",
		 [ConfFile]),
	    {stop, Error}
    end.

start_device(Device, Opts) ->
    case Device of
	{simulated, _Version} ->
	    ?dbg("start_device: running simulated.",[]),
	    {ok, _Pid} = 
		tellstick_drv:start_link([{device,{simulated, ?DEF_VERSION}}]);
	Device ->
	    TOut = proplists:get_value(retry_timeout, Opts, infinity),
	    {ok, _Pid} = 
		tellstick_drv:start_link([{device,Device}, 
					  {retry_timeout, TOut}])
    end.

change_device(NewDevice, _Ctx=#ctx {retry_timeout = TOut}) ->
    tellstick_drv:stop(),
    start_device(NewDevice, [{retry_timeout, TOut}]).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages.
%% Request can be the following:
%% <ul>
%% <li> reload - Reloads the configuration file.</li>
%% <li> new_co_node - Switch of CANopen node.</li>
%% <li> dump - Writes loop data to standard out (for debugging).</li>
%% <li> stop - Stops the application.</li>
%% </ul>
%%
%% @end
%%--------------------------------------------------------------------
-type call_request()::
	{reload, File::atom()} |
	{new_co_node, Id::term()} |
	dump |
	stop.

-spec handle_call(Request::call_request(), From::{pid(), Tag::term()}, Ctx::#ctx{}) ->
			 {reply, Reply::term(), Ctx::#ctx{}} |
			 {noreply, Ctx::#ctx{}} |
			 {stop, Reason::atom(), Reply::term(), Ctx::#ctx{}}.


handle_call({reload, File}, _From, 
	    Ctx=#ctx {node_id = Nid, 
		      device = OldDevice,
		      items = OldItems,
		      events = OldEvents}) ->
    ConfFile = full_filename(File),
    ?dbg("reload ~p",[ConfFile]),
    case load_config(ConfFile) of
	{ok,_Conf=#conf {device=NewDevice,items=NewItems,events=Events}} ->
	    if NewDevice =/= OldDevice ->
		    change_device(NewDevice, Ctx);
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

	    ?dbg("\nold items = ~p\n new items ~p\n "
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

	    clear_events(OldEvents),  %% remove old subscription etc

	    {PifaceInit,Events1} = 
		init_events(Events, [], Ctx#ctx.piface_initialized),
	    {reply, ok, Ctx#ctx {items = NewItems, 
				 events=Events1,
				 device = NewDevice,
				 file=ConfFile,
				 piface_initialized = PifaceInit}};
	Error ->
	    {reply, Error, Ctx}
    end;

handle_call({item_configuration, RemoteId, Channel} = _X, _From, 
	    Ctx=#ctx {items = Items}) ->
    ?dbg("handle_call: received item_configuration req ~p.",[_X]),
    case take_item(RemoteId, Channel, Items) of
	false ->
	    {reply, {error, no_such_item}, Ctx};
	{value,Item,_OtherItems} ->
	    {reply, {ok, bert_format(Item)}, Ctx}
    end;

handle_call({configure_item, RemoteId, Channel, Config} = _X, _From, 
	    Ctx=#ctx {items = Items}) ->
    ?dbg("handle_call: received configure_item req ~p.",[_X]),
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
    ?dbg("handle_call: received device_configuration req.",[]),
    {reply, {ok, bert_format(Device)}, Ctx};

handle_call({configure_device, NewDevice} = _X, _From, 
	    Ctx=#ctx {device = OldDevice}) ->
    ?dbg("handle_call: received configure_device req ~p.",[_X]),
    if NewDevice =/= OldDevice ->
	    change_device(NewDevice, Ctx);
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
	    Ctx=#ctx {device = Device, 
		      co_node = CoNode, 
		      node_id = {Type,Nid},
		      file = File,
		      events = Events,
		      items = Items}) ->
    io:format("Ctx:\n", []),
    io:format("Device = ~p\n", [Device]),
    io:format("CoNode = ~p\n", [CoNode]),
    io:format("NodeId = {~p, ~.16#},\n", [Type, Nid]),
    io:format("Configuration file = ~p\n", [File]),
    io:format("Items=\n", []),
    lists:foreach(fun(Item) -> print_item(Item) end, Items),
    io:format("Events=\n", []),
    lists:foreach(fun(Evt) -> print_event(Evt) end, Events),
    {reply, ok, Ctx};

handle_call(stop, _From, Ctx) ->
    ?dbg("stop:",[]),
    {stop, normal, ok, Ctx};

handle_call(_Request, _From, Ctx) ->
    ?dbg("handle_call: unknown request ~p", [_Request]),
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
    ?dbg("handle_cast: received notify with frame ~w.",[Frame]),
    %% Check index ??
    RemoteId = ?CANID_TO_COBID(Frame#can_frame.id), %% Not X format ??
    <<_F:1, _Addr:7, Ix:16/little, Si:8, Data:4/binary>> = Frame#can_frame.data,
    ?dbg("handle_cast: index = ~.16.0#:~w, data = ~w.",[Ix, Si, Data]),
    try co_codec:decode(Data, unsigned32) of
	{Value, _Rest} ->
	    handle_notify({RemoteId, Ix, Si, Value}, Ctx)
    catch
	error:_Reason ->
	    ?dbg("handle_cast: decode failed, reason ~p.",[_Reason]),
	    {noreply, Ctx}
    end;

handle_cast({analog_output, RemoteId, Channel, Value} = _X, Ctx) ->
    ?dbg("handle_cast: received analog_output ~p.",[_X]),
    handle_notify({RemoteId, ?MSG_ANALOG, Channel, Value}, Ctx);

handle_cast({digital_output, RemoteId, Channel, Value} = _X, Ctx) ->
    ?dbg("handle_cast: received digital_output ~p.",[_X]),
    handle_notify({RemoteId, ?MSG_DIGITAL, Channel, Value}, Ctx);

handle_cast({action, RemoteId, Action, Channel, Value} = _X, Ctx) ->
    ?dbg("handle_cast: received action ~p.",[_X]),
    handle_notify({RemoteId, Action, Channel, Value}, Ctx);

handle_cast({power, RemoteId, ?MSG_POWER_ON} = _X, Ctx) ->
    ?dbg("handle_cast: received power on ~p.",[_X]),
    remote_power_on(RemoteId, Ctx#ctx.node_id, Ctx#ctx.items),
    {noreply, Ctx};    

handle_cast({power, RemoteId, ?MSG_POWER_OFF} = _X, Ctx) ->
    ?dbg("handle_cast: received power off ~p.",[_X]),
    remote_power_off(RemoteId, Ctx#ctx.node_id, Ctx#ctx.items),
    {noreply, Ctx};    

handle_cast({name_change, OldName, NewName}, 
	    Ctx=#ctx {co_node = {name, OldName}}) ->
   ?dbg( "handle_cast: co_node name change from ~p to ~p.", 
	 [OldName, NewName]),
    {noreply, Ctx#ctx {co_node = {name, NewName}}};

handle_cast({name_change, _OldName, _NewName}, Ctx) ->
   ?dbg( "handle_cast: co_node name change from ~p to ~p, ignored.", 
	 [_OldName, _NewName]),
    {noreply, Ctx};

handle_cast({nodeid_change, _TypeOfNid, _OldNid, _NewNid}, 
	    Ctx=#ctx {co_node = CoNode}) ->
   ?dbg( "handle_cast: co_node nodied ~p change from ~p to ~p.", 
	[_TypeOfNid, _OldNid, _NewNid]),
    Nid = co_api:get_option(CoNode, id),
    {noreply, Ctx#ctx {node_id = {name, Nid}}};

handle_cast(_Msg, Ctx) ->
    ?dbg("handle_cast: unknown msg ~p", [_Msg]),
    {noreply, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages.
%% 
%% @end
%%--------------------------------------------------------------------
-type info()::
	{analog_output, Rid::integer(), Rchan::term(), Value::integer()} |
	{'EXIT', Pid::pid(), co_node_terminated} |
	term().

-spec handle_info(Info::info(), Ctx::#ctx{}) -> 
			 {noreply, Ctx::#ctx{}} |
			 {noreply, Ctx::#ctx{}, Timeout::timeout()} |
			 {stop, Reason::term(), Ctx::#ctx{}}.

handle_info({analog_output, Rid, Rchan, Value}, 
	    Ctx=#ctx {node_id = Nid, items = OldItems}) ->
    %% Buffered analog input
    ?dbg("handle_info: analog_output.",[]),
    case take_item(Rid, Rchan, OldItems) of
	false ->
	    ?dbg("handle_info: analog_output, item ~p, ~p not found", 
		 [Rid, Rchan]),
	    {noreply,Ctx};
	{value,Item,OtherItems} ->
	    ?dbg("analog_output: received buffered call for ~.16#, ~p, ~p.",
		 [Rid, Rchan, Value]),
	    NewItems = exec_analog_output(Item,Nid,OtherItems,Value),
	    {noreply, Ctx#ctx { items = NewItems }}
    end;

handle_info({tellstick_event,_Ref,EventData}, Ctx) ->
    ?dbg("handle_info: tellstick event ~p\n.",[EventData]),
    handle_event(EventData, dummy, Ctx),
    {noreply,Ctx};
 
handle_info({gpio_interrupt, 0, ?PIFACE_PIN, _Value} = Event, Ctx) ->
    ?dbg("handle_info: gpio event for piface ~p\n.",[Event]),
    NewCtx = handle_piface_event(Ctx),
    {noreply, NewCtx};

handle_info({gpio_interrupt, PinReg, Pin, Value} = Event, Ctx) ->
    ?dbg("handle_info: gpio event ~p\n.",[Event]),
    EventData = [{protocol,gpio}, 
		 {board, cpu}, 
		 {pin_reg, PinReg}, 
		 {pin, Pin}],
    handle_event(EventData, Value, Ctx),
    {noreply,Ctx};

handle_info({gsms, Ref, _Pdu}, Ctx) ->
    case lists:keyfind(Ref, #event.ref, Ctx#ctx.events) of
	E when is_record(E, event)->
	    %% Send the event as a CAN notification
	    %% It will then be handled by handle_cast above
	    event_notify(dummy, E), %% data must be in event def
	    {noreply, Ctx};
	false ->
	    ?dbg("gsms ref not found, pdu=~p\n", [_Pdu]),
	    {nreply, Ctx}
    end;

handle_info({timeout,Ref,inhibit}, Ctx) ->
    ?dbg("handle_info: inhibit timer done.", []),
    %% inhibit period is overl unlock item
    case lists:keytake(Ref, #item.inhibit, Ctx#ctx.items) of
	{value,I,Is} ->
	    Ctx1 = Ctx#ctx { items = [I#item {inhibit=undefined} | Is]},
	    {noreply, Ctx1};
	false ->
	    {noreply, Ctx}
    end;

handle_info({apply_wait, AItem}, Ctx=#ctx {apply_list = AL}) ->
    ?dbg("handle_info: apply_wait ~p.", [AItem]),
    %% Add item to wait list
    {noreply, Ctx#ctx{apply_list = [AItem | AL]}};

handle_info({apply_timeout, Pid}, Ctx=#ctx {apply_list = AL}) ->
    ?dbg("handle_info: apply_timeout for ~p.", [Pid]),
    case lists:keytake(Pid, #apply_item.pid, AL) of
	{value,_AI=#apply_item {output = OutPut}, NewAL} ->
	    %% Stop Pid ??
	    ?dbg("handle_info: killing ~p.", [Pid]),
	    case erlang:is_process_alive(Pid) of
		true -> exit(Pid, die);
		false -> ok
	    end,
	    %% Maybe create output
	    output({error, timeout}, OutPut),
	    {noreply, Ctx#ctx {apply_list = NewAL}};
	false ->
	    ?dbg("handle_info: Pid ~p not found.", [Pid]),
	    {noreply, Ctx}
    end;

handle_info({apply_result, Pid, Result}, Ctx=#ctx {apply_list = AL}) ->
    ?dbg("handle_info: apply_result ~p for ~p.", [Result, Pid]),
    NewAL = apply_result(Pid, Result, AL),
    {noreply, Ctx#ctx {apply_list = NewAL}};

handle_info({'EXIT', _Pid, normal} = _I, Ctx) ->
    ?dbg("handle_info: ~p, assume normal apply execution.",[_I]),
    {noreply, Ctx};
 
handle_info({'EXIT', _Pid, co_node_terminated}, Ctx) ->
    ?dbg("handle_info: co_node terminated.",[]),
    {stop, co_node_terminated, Ctx};   
 
handle_info({'EXIT', Pid, Reason} = _I, Ctx) ->
    ?dbg("handle_info: ~p, assume abnormal apply execution.",[_I]),
    self() ! {apply_result, Pid, {error, Reason}},
    {noreply, Ctx};
 
handle_info(_Info, Ctx) ->
    ?dbg("handle_info: unknown info ~p", [_Info]),
    {noreply, Ctx}.

%%--------------------------------------------------------------------
%% @private
%%--------------------------------------------------------------------
-spec terminate(Reason::term(), Ctx::#ctx{}) -> 
		       no_return().

terminate(_Reason, _Ctx=#ctx {co_node = CoNode}) ->
    ?dbg("terminate: Reason = ~p",[_Reason]),
    case co_api:alive(CoNode) of
	true ->
	    unsubscribe(CoNode),
	    ?dbg("terminate: unsubscribed.",[]),
	    co_api:detach(CoNode);
	false -> 
	    do_nothing %% Not possible to detach and unsubscribe
    end,
    ?dbg("terminate: detached.",[]),
    tellstick_drv:stop(),
    ?dbg("terminate: driver stopped.",[]),
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

%%--------------------------------------------------------------------
%% Output - control devices etc
%%--------------------------------------------------------------------
handle_notify({RemoteId, _Index = ?MSG_POWER_ON, _SubInd, _Value}, Ctx) ->
    ?dbg("handle_notify power on ~.16#: ID=~7.16.0#:~w, Value=~w", 
	      [RemoteId, _Index, _SubInd, _Value]),
    remote_power_on(RemoteId, Ctx#ctx.node_id, Ctx#ctx.items),
    {noreply, Ctx};    
handle_notify({RemoteId, _Index = ?MSG_POWER_OFF, _SubInd, _Value}, Ctx) ->
    ?dbg("handle_notify power off ~.16#: ID=~7.16.0#:~w, Value=~w", 
	      [RemoteId, _Index, _SubInd, _Value]),
    remote_power_off(RemoteId, Ctx#ctx.node_id, Ctx#ctx.items),
    {noreply, Ctx};    
handle_notify({RemoteId, Index, SubInd, Value}, Ctx) ->
    ?dbg("handle_notify ~.16#: ID=~7.16.0#:~w, Value=~w", 
	      [RemoteId, Index, SubInd, Value]),
    case take_item(RemoteId, SubInd, Ctx#ctx.items) of
	false ->
	    ?dbg("take_item = false", []),
	    {noreply,Ctx};
	{value,I,Is} ->
	    case Index of
		?MSG_DIGITAL ->
		    Items = digital_output(I,Ctx#ctx.node_id,Is,Value),
		    {noreply, Ctx#ctx { items=Items }};
		?MSG_ANALOG ->
		    Items = analog_output(I,Ctx#ctx.node_id,Is,Value),
		    {noreply, Ctx#ctx { items=Items }};
		?MSG_ENCODER ->
		    Items = encoder_output(I,Ctx#ctx.node_id,Is,Value),
		    {noreply, Ctx#ctx { items=Items }};
		_ ->
		    ?dbg("handle_notify ~.16#: ID=~7.16.0#:~w not handled.", 
			 [RemoteId, Index, SubInd]),
		    {noreply,Ctx}
	    end
    end.
    
%%--------------------------------------------------------------------
%% Input - receiving device signals
%%--------------------------------------------------------------------
handle_event(EventData, ActualValue, Ctx) ->
    case take_event(Ctx#ctx.events, EventData) of
	false ->
	    ?dbg("handle_event: event ~p not found", [EventData]),
	    ok;
	E ->
	    %% Send the event as a CAN notification
	    %% It will then be handled by handle_cast above
	    event_notify(ActualValue, E)
    end.

event_notify(ActualValue,_E=#event {value = Value, 
				    type = Type, 
				    rid = Rid, 
				    rchan = Rchan, 
				    polarity = Polarity, 
				    edge = Edge}) ->
    %% Value can be hardcoded in event definition or given by argument
    V = if Value =:= value -> ActualValue;
	   true -> Value
	end,
    %% If polarity flag is true value should be inverted
    V1 = if Polarity -> V bxor 1;
	    true -> V
	 end,
    
    Data = <<V1:32/little>>,
    %% If an interrupt event verify direction against actual value
    case {Edge, ActualValue} of
	{rising,  0} -> do_nothing;
	{falling, 1} -> do_nothing;
	{none, _} -> do_nothing;
	_Other -> co_api:notify(Rid, type2msg(Type),Rchan, Data)
    end.
    

handle_piface_event(Ctx=#ctx {piface_mask = OldMask}) ->
    case call_piface(read_input, []) of
	OldMask ->
	    %% No change, no action
	    ?dbg("handle_piface_event: read input ~p, no change.", [OldMask]),
	    Ctx;
	NewMask when is_integer(NewMask) ->
	    ?dbg("handle_piface_event: read input new ~p, old ~p.", 
		 [NewMask, OldMask]),
	    Changed = NewMask bxor OldMask,
	    %% Loop through mask and see which pins that have been changed
	    piface_pin_event(Changed, 0, NewMask, 
			     Ctx#ctx {piface_mask = NewMask});
	{error, _Reason} ->
	    %% Not possible to get value
	    ?warning("handle_piface_event: read input failed, reason, ~p.", 
		     [_Reason]),
	    Ctx
    end.

piface_pin_event(0, _Pin, _NewMask, Ctx) ->
    ?dbg("piface_pin_event: all sent.", []),
    Ctx;
piface_pin_event(ChangeMask, Pin, NewMask, Ctx) ->
    if (ChangeMask band 1) =:= 1 ->
	    NewValue = (NewMask bsr Pin) band 1,
	    EventData = [{protocol,gpio}, 
			 {board, piface}, 
			 {pin, Pin}],
	    ?dbg("piface_pin_event: event ~p, value ~p.", 
		 [EventData, NewValue]),
	    handle_event(EventData, NewValue, Ctx);
       true ->
	    do_nothing
    end,
    piface_pin_event(ChangeMask bsr 1, Pin + 1, NewMask, Ctx).

%%--------------------------------------------------------------------
%% Digital output
%%--------------------------------------------------------------------
digital_output(I, Nid, Is, Value) ->
    Digital    = proplists:get_bool(digital, I#item.flags),
    SpringBack = proplists:get_bool(springback, I#item.flags),
    if Digital, SpringBack, Value =:= 1 ->
	    Active = not I#item.active,
	    exec_digital_output(I, Nid, Is, Active);
       Digital, not SpringBack ->
	    Active = Value =:= 1,
	    if I#item.active =:= Active -> 
		    ?dbg("digital_output: no change, no action.", []),
		    [I | Is];
	       true ->
		    exec_digital_output(I, Nid, Is, Active)
	    end;
       Digital ->
	    ?dbg("digital_output: no action.", []),
	    ?dbg("item = ~s\n", [fmt_item(I)]),
	    [I | Is];
       true ->
	    ?dbg("digital_output: not digital item.", []),
	    [I | Is]
    end.

exec_digital_output(I, _Nid, Is, true) when I#item.inhibit =/= undefined ->
    ?dbg("digital_output: inhibited.",[]),
    [I|Is];   %% not allowed to turn on yet
exec_digital_output(I, Nid, Is, Active) -> 
    ?dbg("digital_output: executing.",[]),
    ?dbg("item = ~s\n", [fmt_item(I)]),
    case run(I,Active,[]) of
	ok ->
	    AValue = if Active -> 1; true -> 0 end,
	    notify(Nid, pdo1_tx, ?MSG_OUTPUT_ACTIVE, I#item.rchan, AValue),
	    case proplists:get_value(inhibit, I#item.flags, 0) of
		0 ->
		    [I#item { active=Active} | Is];
		T when Active ->
		    TRef = erlang:start_timer(T, self(), inhibit),
		    [I#item { active=Active, inhibit=TRef} | Is];
		_ ->
		    [I#item { active=Active} | Is]
	    end;
	_Error ->
	    ?dbg("digital_output: run failed.",[]),
	    [I | Is]
    end.

%%--------------------------------------------------------------------
%% Analog output
%%--------------------------------------------------------------------
analog_output(I=#item {rid = Rid, rchan = Rchan, timer = Timer, flags = Flags}, 
	     _Nid, Is, Value) ->
    Analog = proplists:get_bool(analog, Flags),
    if Analog ->
	    stop_timer(Timer),
	    ?dbg("analog_output: buffer call for ~.16#, ~p, ~p.",
		 [Rid, Rchan, Value]),
	    Tref = 
		erlang:send_after(100, self(), 
				  {analog_output, Rid, Rchan, Value}),
	    [I#item {timer = Tref} | Is];
       true ->
	    ?dbg("analog_output: not analog item ~p, ~p, ignored.",
		 [Rid, Rchan]),
	    [I | Is]
    end.

exec_analog_output(I=#item {rchan = Rchan, flags = Flags, active = Active}, 
		  Nid, Is, Value) ->
    ?dbg("exec_analog_output: updating item:.",[]),
    ?dbg("item = ~s\n", [fmt_item(I)]),

    Digital = proplists:get_bool(digital, Flags),
    Min     = proplists:get_value(analog_min, Flags, 0),
    Max     = proplists:get_value(analog_max, Flags, 255),
    Style   = proplists:get_value(style, Flags, smooth),
    %% Calculate actual level
    %% Scale 0-65535 => Min-Max
    IValue = trunc(Min + (Max-Min)*(Value/65535)),
    %% scale Min-Max => 0-65535 (adjusting the slider)
    RValue = trunc(65535*((IValue-Min)/(Max-Min))),

    ?dbg("analog_output: calling driver with new value ~p",[IValue]),
    case run(I,IValue,[{style, Style}]) of
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

%%--------------------------------------------------------------------
%% Encoder output
%%--------------------------------------------------------------------
encoder_output(_Nid, I, Is, _Value) ->
    ?dbg("encoder_output: Not implemented yet.",[]),
    [I|Is].

%%--------------------------------------------------------------------
%% Execution of both control and event signalling
%%--------------------------------------------------------------------
run(_I=#item {type = email}, false, _Style) ->
    ?dbg("run email: state false, not sending.",[]),
    ok;  %% do not send
run(_I=#item {type = email, flags = Flags}, true, _Style) ->
    Sender = proplists:get_value(sender, Flags),
    Recipients = proplists:get_value(recipients, Flags),
    Body = proplists:get_value(body, Flags),
    ?dbg("run email: sending to ~p",[Recipients]),
    %% fixme: setup callback and log failed attempts
    Flags1 = lists:foldl(fun(F,Fs) -> proplists:delete(F, Fs) end, 
			 Flags,
			 [digital,springback,inhibit,
			  sender,recipients,
			  from,to,subject,body
			 ]),
    From = case proplists:get_value(from, Flags) of
	       undefined -> [];
	       F1 -> [["From: ", F1]]
	   end,
    To = case proplists:get_value(to, Flags) of
	     undefined -> [];
	     F3 -> [["To: ", F3]]
	 end,
    Subject = case proplists:get_value(subject, Flags) of
		  undefined -> [];
		  F2 -> [["Subject: ", F2]]
	      end,
    Date = case proplists:get_value(date, Flags, true) of
	       true ->
		   [["Date: ", smtp_util:rfc5322_timestamp()]];
	       false ->
		   [];
	       Date1 when is_list(Date1) -> [["Date: ", Date1]]
	   end,
    MessageID = case proplists:get_value(message_id, Flags, true) of
		    true ->
			[["Message-ID:", smtp_util:generate_message_id()]];
		    false ->
			[];
		    MID ->
			[["Message-ID:", MID]]
		end,
    Headers1 = 
	[ [H,"\r\n"] || 
	    H <- From ++ To ++ Subject ++ Date ++ MessageID ],
    Message = [Headers1,"\r\n",Body],
    case gen_smtp_client:send({Sender, Recipients, Message}, Flags1) of
	{ok,_Pid} ->
	    ok;
	Error -> Error
    end;
run(_I=#item {type = sms}, false, _Style) ->
    ?dbg("run sms: state false, not sending.",[]),
    ok;  %% do not send
run(_I=#item {type = sms, flags = Flags}, true, _Style) ->
    Body = proplists:get_value(body, Flags, ""),
    {Fs,_} = proplists:split(Flags, [smsc,rp,udhi,udh,srr,mref,
				     vpf,vp,addr,pid,dcs,type,class,
				     alphabet,compression,store,wait_type,
				     notify,ref]),
    Opts = lists:append(Fs),
    gsms:send(Opts, Body);

run(I=#item {type = exodm, unit = Mod, lchan = Fun, flags = Flags}, 
    Active, _Style) ->
    ExodmArgs = rpc_args(I, Active, proplists:get_value(args, Flags, []), []),
    ?dbg("run exodm: M = ~p, F = ~p, A = ~p.",[Mod, Fun, ExodmArgs]),
    case exoport:rpc(exodm_rpc, rpc, [atom_to_binary(Mod, latin1), 
				      atom_to_binary(Fun, latin1), 
				      ExodmArgs]) of
	{reply,[{result,<<"accepted">>}],[]} ->
	    ?dbg("run exodm result ok", []),
	    ok;
	_Other ->
	    ?dbg("run exodm result ~p", [_Other]),
	    ?ee("rpc call ~p:~p(~p) failed",[Mod, Fun, ExodmArgs]),
	    {error, rpc_call_failed}
    end;

run(_I=#item {type = apply, unit = Mod, lchan = Fun, flags = Flags}, 
    Active, _Style) ->
    Args = apply_args(Active, proplists:get_value(args, Flags, []),[]),
    TimeOut = proplists:get_value(timeout, Flags, 5000),
    OutPut = proplists:get_value(output, Flags, []),
    ?dbg("run apply: M = ~p, F = ~p, A = ~p.",[Mod, Fun, Args]),
    case execute_mfa(Mod,Fun,Args) of
 	Pid when is_pid(Pid) ->
	    TRef = erlang:start_timer(TimeOut, self(), {apply_timeout, Pid}),
	    self() ! {apply_wait, #apply_item {pid = Pid, 
					       output = OutPut,
					       timer = TRef}},
	    ok;
	_Other ->
	    ?dbg("run apply result ~p", [_Other]),
	    ?ee("call ~p:~p(~p) failed",[Mod, Fun, Args]),
	    {error, call_failed}
    end;

run(_I=#item {type = gpio, unit = PinReg, lchan = Pin, flags = Flags}, 
    true, _Style) ->
    ?dbg("run gpio set: PinReg = ~p, Pin = ~p, Flags = ~p.",
	 [PinReg, Pin, Flags]),
    case proplists:get_value(board, Flags, cpu) of
	cpu -> 
	    ?dbg("action: gpio, set PinReg = ~w, Pin = ~p.", 
		 [PinReg, Pin]),
	    call_gpio(set, [PinReg, Pin]);
	piface ->
	    ?dbg("action: gpio, piface set Pin = ~p.", [Pin]),
	    call_piface(gpio_set, [Pin]);
	_Other ->
	    %% ignore
	    ok
    end;
run(_I=#item {type = gpio, unit = PinReg, lchan = Pin, flags = Flags}, 
    false, _Style) ->
    ?dbg("run gpio clr: PinReg = ~p, Pin = ~p, Flags = ~p.",
	 [PinReg, Pin, Flags]),
    case proplists:get_value(board, Flags, cpu) of
	cpu -> 
	    ?dbg("action: gpio, clr PinReg = ~w, Pin = ~p.", 
		 [PinReg, Pin]),
	    call_gpio(clr, [PinReg, Pin]);
	piface ->
	    ?dbg("action: gpio, piface clr Pin = ~p.", [Pin]),
	    call_piface(gpio_clr, [Pin]);
	_Other ->
	    %% ignore
	    ok
    end;
run(_I=#item {type = Type, unit = Unit, lchan = Chan}, Active, Style) ->
    Args = [Unit,Chan,Active,Style],
    ?dbg("action: Type = ~p, Args = ~w.", [Type, Args]),
    try apply(tellstick_drv, Type, Args) of
	ok ->
	    ok;
	Error ->
	    ?dbg("tellstick_drv: error=~p.", [Error]),
	    Error
    catch
	exit:Reason ->
	    ?dbg("tellstick_drv: crash=~p.", [Reason]),
	    {error,Reason};
	error:Reason ->
	    ?dbg("tellstick_drv: crash=~p.", [Reason]),
	    {error,Reason}
    end.

%%--------------------------------------------------------------------
%% Execution of function call items
%%--------------------------------------------------------------------
execute_mfa(M,F,A) 
  when is_atom(M), is_atom(F), is_list(A) ->
    ?dbg("execute: ~p:~p(~p).\n",[M,F,A]),
    case proc_lib:spawn_link(?MODULE, execute_mfa, [M,F,A,  self()]) of
	Pid when is_pid(Pid) -> 
	    ?dbg("execute: spawned = ~p.",[Pid]),
	    Pid;
	_Other ->
	    ?dbg("execute: spawned failed, result ~p.",[_Other]),
	    {error, execute_failed}
    end;
execute_mfa(M,F,A) ->
    ?dbg("execute: ~p:~p(~p) is illegal.",[M,F,A]),
    {error, illegal_format}.
    
execute_mfa(M,F,A, Starter) -> 
    %% Need to sleep a little so that the server can storethe Pid
    timer:sleep(10),
    try apply(M,F,A) of
	Result ->
	    Starter ! {apply_result, self(), Result}
    catch
	error:Reason ->
	    ?dbg("execute: catch Reason = ~p",[Reason]), 
	    Starter ! {apply_result, self(), {error, Reason}}
    end.


%%--------------------------------------------------------------------
%% Handle result of execution of function call items
%%--------------------------------------------------------------------
apply_result(Pid, Result, ApplyList) ->		        
   case lists:keytake(Pid, #apply_item.pid, ApplyList) of
	{value, _AI=#apply_item {output = OutPut, timer = TRef}, NewAL} ->
	   ?dbg("apply_result: ~p found in apply list.",[_AI]),
	    stop_timer(TRef),
	    %% Maybe create output
	    output(Result, OutPut),
	    NewAL;
	false ->
	    ?dbg("apply_result: ~p not found.", [Pid]),
	    ApplyList
    end.

output(Result, OutPut) when is_list(OutPut) ->
    ?dbg("output: search in ~p for result ~p",[OutPut, Result]),
    %% Use match spec to see if Result exists in Output list
    %%  [{MatchHead = {<received result>, <rest of output tuple>}, 
    %%    MatchCond = <no conditions>, 
    %%    MatchBody = [return whole tuple]}]
    MatchSpec = [{{Result, '_'}, [], ['$_']}],
    CompMatchSpec = ets:match_spec_compile(MatchSpec),
    output(ets:match_spec_run(OutPut, CompMatchSpec)).

output([]) ->
    ?dbg("output: no more output matching result",[]),
    ok;
output([{_Result, {Rid, RChannel, Type, Value} = _O} | Rest]) ->
    ?dbg("output: ~p matched result ~p",[_O, _Result]),
    Data = <<Value:32/little>>,
    co_api:notify(rid_translate(Rid), type2msg(Type), RChannel, Data),
    output(Rest).
	    
%%--------------------------------------------------------------------
%% Init of items/events
%%--------------------------------------------------------------------
power_on(Nid, ItemsToAdd) ->
    power_command(Nid, ?MSG_OUTPUT_ADD, ItemsToAdd).

power_off(Nid, ItemsToRemove) ->
    power_command(Nid, ?MSG_OUTPUT_DEL, ItemsToRemove).

power_command(_Nid, _Cmd, []) ->
    ok;
power_command(Nid, Cmd, [I | Items]) ->
    Value = ((I#item.rid bsl 8) bor I#item.rchan) band 16#ffffffff, %% ??
    notify(Nid, pdo1_tx, Cmd, I#item.rchan, Value),
    init_if_gpio(Cmd, I),
    power_command(Nid, Cmd, Items).

init_if_gpio(?MSG_OUTPUT_ADD, 
	     _I=#item {type = gpio, unit = PinReg, lchan = Pin, flags = Flags}) ->
    case proplists:get_value(board, Flags, cpu) of
	cpu -> 
	    call_gpio(init, [PinReg, Pin]),
	    call_gpio(set_direction, [PinReg, Pin, out]),
	    ok;
	piface ->	    
	    ok;
	_Board ->
	    ?dbg("init_gpio_port: not supported board ~p",[_Board])
    end;
init_if_gpio(_Cmd, _I) -> %% Release case ??
    ok.

reset_items(Items) ->
    lists:foreach(
      fun(I) ->
	      ?dbg("reset_items: resetting ~p, ~p, ~p", 
		   [I#item.type,I#item.unit,I#item.lchan]),
	      %% timer:sleep(1000), %% Otherwise rfzone chokes ..
	      Fs = I#item.flags,
	      Analog = proplists:get_bool(analog, Fs),
	      Digital = proplists:get_bool(digital, Fs),
	      if Digital ->
		      run(I,false,[]);
		 Analog ->
		      run(I,0,[{style, instant}])
	      end
      end,
      Items).

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

init_events([],Acc,Pi) ->
    {Pi,lists:reverse(Acc)};
init_events([E=#event {pattern = Pattern} | Rest],Acc,Pi) ->
    case proplists:get_value(protocol, Pattern) of
	gpio ->
	    PinReg = proplists:get_value(pin_reg, Pattern, 0),
	    Pin = proplists:get_value(pin, Pattern),
	    Edge = proplists:get_value(interrupt, Pattern, none),
	    case proplists:get_value(board, Pattern, cpu) of
		cpu -> 
		    ?dbg("cpu set interrupt ~p\n", [{PinReg, Pin, Edge}]),
		    call_gpio(set_interrupt, [PinReg, Pin, Edge]),
		    init_events(Rest, [E|Acc], Pi);
		piface ->
		    ?dbg("piface set interrupt ~p\n", [{PinReg, Pin, Edge}]),
		    if Edge =/= none, 
		       Pi =:= false ->
			    ?dbg("piface init_interrupt", []),
			    call_piface(init_interrupt, []),
			    call_gpio(init, [?PIFACE_PIN]), 
			    call_gpio(set_interrupt, [?PIFACE_PIN, falling]),
			    init_events(Rest, [E|Acc], true);
		       true ->
			    init_events(Rest, [E|Acc], Pi)
		    end;
		_ ->
		    init_events(Rest, [E|Acc], Pi)
	    end;
	sms ->
	    Filter = sms_filter(Pattern),
	    ?dbg("sms filter = ~p\n", [Filter]),
	    case gsms:subscribe(Filter) of
		{ok,Ref} ->
		    init_events(Rest, [E#event{ref=Ref}|Acc], Pi);
		_Error ->
		    ?error("unable to subscribe to sms ~p", [_Error]),
		    init_events(Rest, [E|Acc], Pi)
	    end;
	_Other -> 
	    init_events(Rest, [E|Acc], Pi)
    end.

clear_events([E=#event {pattern = Pattern} | Rest]) ->
    case proplists:get_value(protocol, Pattern) of
	sms ->
	    gsms:unsubscribe(E#event.ref),
	    clear_events(Rest);
	_ ->
	    clear_events(Rest)
    end;
clear_events([]) ->
    ok.


%%--------------------------------------------------------------------
%% Load configuration file
%%--------------------------------------------------------------------
load_config(File) ->
    case file:consult(File) of
	{ok, Cs} ->
	    load_conf(Cs,#conf{},[],[]);
	Error -> Error
    end.

load_conf([C | Cs], Conf, Is, Ts) ->
    case C of
	{Rid,Rchan,Type,Unit,Chan,Flags} ->
	    RCobId = rid_translate(Rid),
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
	{event, Pattern, {Rid,RChan,Type,Value}} ->
	    RCobId = rid_translate(Rid),
	    Polarity = proplists:get_value(polarity, Pattern, false),
	    Edge = proplists:get_value(interrupt, Pattern, undefined),
	    Item = #event { pattern = Pattern,
			    rid   = RCobId,
			    rchan = RChan,
			    type  = Type,
			    value = Value,
			    edge = Edge,
			    polarity = Polarity},
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
    ?dbg("Loaded items: \n ",[]),
    lists:foreach(fun(I) -> ?dbg("~s", [fmt_item(I)]) end, Is),
    ?dbg("Loaded events: \n ",[]),
    lists:foreach(fun(E) -> ?dbg("~s", [fmt_event(E)]) end, Ts),
    if Conf#conf.product =:= undefined ->
	    {error, no_product};
       true ->
	    {ok, Conf#conf {items=Is,events=Ts}}
    end.

%%--------------------------------------------------------------------
%% Localize items/events
%%--------------------------------------------------------------------
take_item(Rid, Rchan, Items) ->
    take_item(Rid, Rchan, Items, []).

take_item(Rid, Rchan, [I=#item {rid=Rid,rchan=Rchan}|Is], Acc) ->
    {value,I,Is++Acc};
take_item(Rid, Rchan, [I|Is],Acc) ->
    take_item(Rid,Rchan,Is,[I|Acc]);
take_item(_Rid, _Rchan, [],_Acc) ->
    false.


take_event([E=#event { pattern=Pattern }|Ts], EventData) ->
    case match_event(Pattern, EventData) of
	true -> E;
	false -> take_event(Ts, EventData)
    end;
take_event([], _EventData) ->
    false.

match_event([{Key,_Value}|Kvs], EventData) 
  when Key == polarity;
       Key == interrupt ->
    %% Ignore now
    match_event(Kvs, EventData);
match_event([{Key,Value}|Kvs], EventData) ->
    case lists:keytake(Key, 1, EventData) of
	{value,{Key,Value},EventData1} -> match_event(Kvs,EventData1);
	_ -> false
    end;
match_event([], _EventData) ->
    true.
	    
%%--------------------------------------------------------------------
%% Configuration of items
%%--------------------------------------------------------------------
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


%%--------------------------------------------------------------------
%% Verify item/event configuration
%%--------------------------------------------------------------------
verify_item(_I=#item {type = email, 
		      unit = _Unit, 
		      lchan = _Lchan,
		      flags = Opts}) ->
    verify_mail_options(Opts);

verify_item(_I=#item {type = sms, 
		      unit = _Unit, 
		      lchan = _Lchan,
		      flags = Opts}) ->
    verify_sms_options(Opts);

verify_item(I=#item {type = exodm = Type, 
		     unit = Mod, 
		     lchan = Fun, 
		     flags = Flags}) 
  when is_atom(Mod), is_atom(Fun), is_list(Flags) ->
    verify_flags(Type, Flags, I);

verify_item(_I=#item {type = exodm, 
		      unit = _Mod, 
		      lchan = _Fun, 
		      flags = _Args}) ->
    ?dbg("verify_item: illegal exodm format, mod ~p, fun ~p, args ~p.",
	 [_Mod, _Fun, _Args]),
    {error, illegal_exodm_format};

verify_item(I=#item {type = apply = Type, 
		     unit = Mod, 
		     lchan = Fun, 
		     flags = Flags}) 
  when is_atom(Mod), is_atom(Fun), is_list(Flags) ->
    verify_flags(Type, Flags, I);

%% The rest are remote control types
verify_item(I=#item {}) ->
    verify_rf(I).
 
verify_rf(I=#item {type = Type, 
		   unit = Unit, 
		   lchan = Channel, 
		   flags = Flags}) ->
    case verify_unit_range(Type, Unit) of
	ok ->
	    case verify_channel_range(Type, Channel) of
		ok ->
		    Analog = proplists:get_bool(analog, Flags),
		    Digital = proplists:get_bool(digital, Flags),
		    if Analog orelse Digital ->
			    verify_flags(Type, Flags, I);
		       true ->
			    {error, must_be_digital_or_analog}
		    end;
		{error, _Reason} = N->
		    N
	    end;
	{error, _Reason} = N ->
	    N
    end.

verify_apps_started([]) ->
    true;
verify_apps_started([App | Apps]) ->
    case verify_app_started(App) of
	true -> verify_apps_started(Apps);
	false -> false
    end.
	    
verify_app_started(App) ->
    case lists:keymember(App, 1, application:which_applications()) of
	true ->
	    true;
	false ->
	    %% Special handling of hardware io apps
	    case {get(on_host), App} of
		{true, A} when A =:= gpio;
			       A =:= spi;
			       A =:= piface -> 
		    true;
		_Other -> 
		    ?warning("application ~p not runnning", [App]),
		    false
	    end
    end.

verify_event(_I=#event {pattern = Pattern, 
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
		    _ -> 
			?dbg("verify_event: illegal type ~p.", [Type]),
			false
		end
       end, {error, bad_channel_type},

       fun() -> case Type of
		    analog when Value >= 0, Value =< 16#ffff ->
			true;
		    digital when Value =:= 0; Value =:= 1 ->
			true;
		    digital when Value =:= value ->
			%% Value will be taken from input
			true;
		    encoder -> is_integer(Value);
		    _ -> 
			?dbg("verify_event: illegal type/value ~p/~p.", 
			     [Type, Value]),
			false
		end
       end, {error, bad_value_range},

       fun() -> case proplists:get_value(apps, Pattern, []) of
		    [] -> true;
		    AppList -> verify_apps_started(AppList)
		end
       end, {error, app_not_started},

       fun() ->
	       case proplists:get_value(protocol, Pattern) of
		   gpio ->
		       verify_gpio_event(Pattern);
		   sms ->
		       verify_sms_event(Pattern);
		   _ ->
		       verify_event(Pattern, [protocol,model,data])
	       end
       end,
       {error, bad_event}

      ]).


verify_sms_options([{K,V}|Opts]) ->
    case verify_sms_option(K,V) of
	false -> {error, {K, bad_value}};
	true -> verify_sms_options(Opts);
	unknown -> {error,{unknown_option, K}}
    end;
verify_sms_options([K|Opts]) ->
    case verify_sms_option(K) of
	true -> verify_sms_options(Opts);
	unknown -> {error,{unknown_option, K}}
    end;
verify_sms_options([]) ->
    ok.

verify_sms_option(inhibit,Value) ->
    is_inhibit_value(Value);
verify_sms_option(digital,Value) ->
    is_boolean(Value);
verify_sms_option(springback,Value) ->
    is_boolean(Value);
verify_sms_option(body,Value) ->
    is_list(Value);
verify_sms_option(apps,AppList) ->
    verify_apps_started(AppList);
verify_sms_option(K,_V) ->
    case lists:member(K, [smsc,rp,udhi,udh,srr,mref,
			  vpf,vp,addr,pid,dcs,type,class,
			  alphabet,compression,store,wait_type,
			  notify,ref]) of
	true -> true;
	false -> unknown
    end.
	     


verify_sms_option(digital) -> true;
verify_sms_option(springback) -> true;
verify_sms_option(_) -> unknown.


verify_mail_option(inhibit,Value) ->   
    is_inhibit_value(Value);
verify_mail_option(sender,Value) ->    
    is_mail_address(Value);
verify_mail_option(recipients,Vs) ->
    lists:all(fun(A) -> is_mail_address(A) end, Vs);
verify_mail_option(subject,Value) ->
    is_string(Value);
verify_mail_option(from,Value) ->
    is_string(Value);
verify_mail_option(to,Value) ->
    is_string(Value);
verify_mail_option(date,Value) ->
    is_boolean(Value) orelse is_string(Value);
verify_mail_option(message_id,Value) ->
    is_boolean(Value) orelse is_string(Value);
verify_mail_option(body,Value) ->
    is_string(Value);
verify_mail_option(relay,Value) ->
    is_address(Value);
verify_mail_option(auth,Value) ->
    is_string(Value);
verify_mail_option(username,Value) ->
    is_string(Value);
verify_mail_option(password,Value) ->
    is_string(Value);
verify_mail_option(no_mx_lookups,Value) ->
    is_boolean(Value);
verify_mail_option(retries,Value) ->
    if is_integer(Value), Value >= 0 ->
	    true;
       true -> false
    end;
verify_mail_option(tls,Value) ->
    is_boolean(Value);
verify_mail_option(ssl,Value) ->
    is_boolean(Value);
verify_mail_option(port,Value) ->
    if is_integer(Value), Value > 0, Value =< 16#ffff ->
	    true;
       true -> false
    end;
verify_mail_option(digital,Value) ->
    is_boolean(Value);
verify_mail_option(springback,Value) ->
    is_boolean(Value);
verify_mail_option(apps,AppList) ->
    verify_apps_started(AppList);
verify_mail_option(_,_) ->
    unknown.

verify_mail_option(digital) -> true;
verify_mail_option(springback) -> true;
verify_mail_option(_) -> unknown.


verify_mail_options([{K,V}|Opts]) ->
    case verify_mail_option(K,V) of
	false -> {error, {K, bad_value}};
	true -> verify_mail_options(Opts);
	unknown -> {error,{unknown_option, K}}
    end;
verify_mail_options([K|Opts]) ->
    case verify_mail_option(K) of
	true -> verify_mail_options(Opts);
	unknown -> {error,{unknown_option, K}}
    end;
verify_mail_options([]) ->
    ok.

is_string(Value) ->	
    try iolist_size(Value) of
	_ -> true
    catch
	error:_ -> false
    end.

is_mail_address(Name) when is_binary(Name) ->
    is_mail_address(binary_to_list(Name));
is_mail_address([$<|Addr1]) ->
    case lists:reverse(Addr1) of
	[$>|Addr2] -> is_mail_address(lists:reverse(Addr2));
	_ -> false
    end;
is_mail_address(Addr) when is_list(Addr) ->
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
is_mail_address(_) ->
    false.

%% max inhibit is about 37 hours!
is_inhibit_value(Value) when
      is_integer(Value), Value > 0, Value =< 16#7FFFFFF ->
    true;
is_inhibit_value(_) ->
    false.

is_address(Value) ->
    is_domain_name(Value) orelse
	is_ip_string(Value) orelse
	is_ip_address(Value).

is_domain_name(Value) ->
    inet_parse:domain(Value).

is_ip_string(Value) ->
    is_ipv4_string(Value) orelse
	is_ipv6_string(Value).

is_ipv4_string(Value) ->	
    try inet_parse:ipv4_address(Value) of
	{ok,_} -> true;
	{error,einval} -> false
    catch
	error:_ -> false
    end.

is_ipv6_string(Value) ->
    try inet_parse:ipv6_address(Value) of
	{ok,_} -> true;
	{error,einval} -> false
    catch
	error:_ -> false
    end.

is_ip_address(Addr) ->	
    is_ipv4_addr(Addr) orelse
	is_ipv6_addr(Addr).

is_ipv4_addr({A,B,C,D}) 
  when (A bor B bor C bor D) band (bnot 16#ff) =:= 0 ->
    true;
is_ipv4_addr(_) ->
    false.

is_ipv6_addr({A,B,C,D,E,F,G,H}) 
  when (A bor B bor C bor D bor E bor F bor G bor H) 
       band (bnot 16#ffff) =:= 0 ->
    true;
is_ipv6_addr(_) ->
    false.
	    

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
verify_event(_E, []) ->
    ?dbg("verify_event: unexpected key(s) ~p.", [_E]),
    false.

%% take subset of proplist
sms_filter(Pattern) ->
    {Fs,_Pattern1} = proplists:split(Pattern, [type,class,alphabet,pid,src,dst,
					       anumber,bnumber,smsc,reg_exp]),
    lists:append(Fs).

verify_sms_event(Event) ->
    %% fixme add filter and or not
    verify_event(Event, [protocol,data,polarity,
			 type,class,alphabet,pid,src,dst,
			 anumber,bnumber,smsc,reg_exp,
			 apps]).


verify_gpio_event(Event) ->
    %% Pin is mandatory
    case lists:keymember(pin, 1, Event) of
	true ->
	    %% Optional 
	    verify_event(Event, 
			 [protocol,board,pin_reg,pin,data,
			  interrupt,polarity,
			  apps]);
	false ->
	    ?dbg("verify_gpio_event: missing pin",[])
    end.
		    

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
verify_unit_range(gpio, PinReg) 
  when PinReg >= 0,
       PinReg =< 1 ->
    ok;
verify_unit_range(_Type, _Unit) ->
    ?dbg("verify_unit_range: invalid type/unit combination ~p,~p", 
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
  when Channel >= 0,
       Channel =< 4 ->
    ok;
verify_channel_range(gpio, Pin)
  when Pin >= 0,
       Pin =< 255 -> 
    ok;
verify_channel_range(_Type, _Channel) ->
    ?dbg("verify_channel_range: invalid type/channel combination ~p,~p", 
		   [_Type, _Channel]),
    {error, invalid_type_channel_combination}.


verify_flags(_Type, [], _I) ->
    ok;
verify_flags(Type, [{apps, AList} | Flags], I) ->
    case verify_apps_started(AList) of
	true -> verify_flags(Type, Flags, I);
	false -> {error, needed_app_not_started}
    end;
verify_flags(Type, [{args, _ArgList} | Flags], I) 
  when Type == exodm;
       Type == apply ->
    %% Check args ??
    verify_flags(Type, Flags, I);
verify_flags(apply = Type, [{output, _OutPut} | Flags], I) ->
    %% Check output ??
    verify_flags(Type, Flags, I);
verify_flags(Type, [digital | Flags], I) ->
    %% Always OK?
    verify_flags(Type, Flags, I);
verify_flags(Type, [springback | Flags], I) ->
    %% Always OK?
    verify_flags(Type, Flags, I);
verify_flags(Type, [analog | Flags], I) 
  when Type == nexax;
       Type == ikea ->
    verify_flags(Type, Flags, I);
verify_flags(ikea = Type, [{analog_min, Min} | Flags], I) 
  when Min >= 0, Min =< 10 ->
    verify_flags(Type, Flags, I);
verify_flags(ikea = Type, [{analog_max, Max} | Flags], I) 
  when Max >= 0, Max =< 10 ->
    verify_flags(Type, Flags, I);
verify_flags(ikea = Type, [{style, Style} | Flags], I) 
  when Style == smooth;
       Style == instant ->
    verify_flags(Type, Flags, I);
verify_flags(nexax = Type, [{analog_min, Min} | Flags], I) 
  when Min >= 0, Min =< 255 ->
    verify_flags(Type, Flags, I);
verify_flags(nexax = Type, [{analog_max, Max} | Flags], I) 
  when Max >= 0, Max =< 255 ->
    verify_flags(Type, Flags, I);
verify_flags(gpio = Type, [{board, cpu} | Flags], I) ->
    verify_flags(Type, Flags, I);
verify_flags(gpio = Type, [{board, piface} | Flags], 
	     I=#item {unit = 0, lchan = Pin}) 
  when Pin >= 0,
       Pin =< 7 ->
    verify_flags(Type, Flags, I);
verify_flags(gpio, [{board, piface} | _Flags], _I)  ->
    {error, invalid_board_pin_combination};
verify_flags(gpio, [{board, _Board} | _Flags], _I) ->
    {error, not_supported_board};
verify_flags(gpio = Type, [{interrupt, Edge} | Flags], I) 
  when Edge == none;
       Edge == falling;
       Edge == rising;
       Edge == both ->
    verify_flags(Type, Flags, I);
verify_flags(Type, [{inhibit,Time} | Flags], I)
  when is_integer(Time), Time >= 0 ->
    verify_flags(Type, Flags, I);
verify_flags(Type, [{timeout,Time} | Flags], I)
  when (Type == apply orelse Type == exodm),
       is_integer(Time), Time >= 0 ->
    verify_flags(Type, Flags, I);
verify_flags(_Type, [_Flag | _Flags], _I) ->
    ?dbg("verify_flags: invalid type/flag combination ~p,~p", 
		   [_Type, _Flag]),
    {error, invalid_type_flag_combination}.

%%--------------------------------------------------------------------
%% Conversion to bert format
%%--------------------------------------------------------------------
bert_format({simulated, _Version}) ->
    [{'tellstick-device', simulated}];
bert_format({Device, Version}) ->
    [{'tellstick-device', Device}, {version, Version}];
bert_format(_I=#item{rid = RemoteId, rchan = RChannel, 
		     active = Active, type = Type,
		     unit = Unit, lchan = DeviceChannel,
		     flags = Flags, level = Level}) ->
    Common = [{'remote-id', 
	       [{'type-of-cobid', xcobid},
		{'function-code',pdo1_tx},
		{'remote-node-id', RemoteId}]},
	      {'remote-channel', RChannel},
	      {state, if Active == true -> on; Active == false -> off end},
	      {protocol, Type},
	      {channel, DeviceChannel},
	      {flags, bert_format_flags(Flags)}],
    DevChan = if Type == sartano -> []; true -> [{unit, Unit}] end,
    Lev = case lists:member(analog, Flags) of
	      false -> [];
	      true -> [{level, Level}]
	  end,
    Common ++ DevChan ++ Lev.

bert_format_flags(Flags) ->
    bert_format_flags(Flags, []).

bert_format_flags([{Key, _Value} = Flag | Rest], Acc) when is_atom(Key) -> 
    bert_format_flags(Rest, [Flag | Acc]);
bert_format_flags([Key | Rest], Acc) when is_atom(Key) -> 
    bert_format_flags(Rest, [{Key, true} | Acc]);
bert_format_flags([], Acc) -> Acc.

		          
%%--------------------------------------------------------------------
%% Debug printing
%%--------------------------------------------------------------------
fmt_item(I) when is_record(I,item) ->
    io_lib:format("{rid:~.16#,rchan:~p,type:~p,unit:~p,chan:~p,~n"
		  "active:~p,level:~p,~nflags=~s}",
		  [I#item.rid, I#item.rchan, 
		   I#item.type,I #item.unit, I#item.lchan, 
		   I#item.active, I#item.level,
		   fmt_flags(I#item.flags)]).

fmt_event(E) when is_record(E, event) ->
    io_lib:format("{~p,~nrid:~.16#,rchan:~w,type:~w,value:~w}", 
		  [E#event.pattern,E#event.rid,E#event.rchan, E#event.type,
		   E#event.value]).
    
print_item(I) when is_record(I,item) ->
    io:format("item: ~s\n", [fmt_item(I)]).

print_event(E) when is_record(E, event) ->
    io:format("event: ~s\n", [fmt_event(E)]).

fmt_flags([Flag|Tail]) ->
    [io_lib:format("~p~n", [Flag]) | fmt_flags(Tail)];
fmt_flags([]) -> "".

  
%%--------------------------------------------------------------------
%% Utilities
%%--------------------------------------------------------------------
%% @private
rid_translate({xcobid, Func, Nid}) ->
    ?XCOB_ID(co_lib:encode_func(Func), Nid);
rid_translate({cobid, Func, Nid}) ->
    ?COB_ID(co_lib:encode_func(Func), Nid).


type2msg(digital) -> ?MSG_DIGITAL;
type2msg(analog) -> ?MSG_ANALOG;
type2msg(encoder) -> ?MSG_ENCODER.
    
notify(Nid, Func, Ix, Si, Value) ->
    co_api:notify_from(Nid, Func, Ix, Si,co_codec:encode(Value, unsigned32)).
    

full_filename(FileName) ->
    case filename:dirname(FileName) of
	"." when hd(FileName) =/= $. ->
	    filename:join(code:priv_dir(rfzone), FileName);
	_ -> 
	    FileName
    end.

subscribe(CoNode) ->
    ?dbg("subscribe: IndexList = ~w",[?COMMANDS]),
    lists:foreach(fun({{Index, _SubInd}, _Type, _Value}) ->
			  co_api:extended_notify_subscribe(CoNode, Index)
		  end, ?COMMANDS).
unsubscribe(CoNode) ->
    ?dbg("unsubscribe: IndexList = ~w",[?COMMANDS]),
    lists:foreach(fun({{Index, _SubInd}, _Type, _Value}) ->
			  co_api:extended_notify_unsubscribe(CoNode, Index)
		  end, ?COMMANDS).

%% If needed add {value, Active}
rpc_args(_I=#item {}, _Active, [], Acc) ->
    lists:reverse(Acc);
rpc_args(I=#item {}, Active, [{_Key, _Value} = Arg | Args], Acc) ->
    rpc_args(I, Active, Args, [Arg | Acc]);
rpc_args(I=#item {}, Active, [rfzone_active_value = Key | Args], Acc) ->
    rpc_args(I, Active, Args, [{Key, bool2int(Active)} | Acc]).

%% If needed add Active
apply_args(_Active, [], Acc) ->
    lists:reverse(Acc);
apply_args(Active, [rfzone_active_value | Args], Acc) ->
    apply_args(Active, Args, [Active | Acc]);
apply_args(Active, [Arg | Args], Acc) ->
    apply_args(Active, Args, [Arg | Acc]).

bool2int(true) -> 1;
bool2int(false) -> 0.
    
encode(on)      -> ?MSG_POWER_ON;
encode(off)     -> ?MSG_POWER_OFF;
encode(digital) -> ?MSG_DIGITAL;
encode(analog)  -> ?MSG_ANALOG;
encode(encoder) -> ?MSG_ENCODER.
     
stop_timer(undefined) ->
    undefined;
stop_timer(Ref) ->
    erlang:cancel_timer(Ref).


%% if on_host is true no io-pins are accessible
call_piface(F, Args) ->
    case get(on_host) of
	true -> apply(io_stub, F, Args);
	_Else -> apply(piface, F, Args)
    end.

call_gpio(F, Args) ->
    case get(on_host) of
	true -> apply(io_stub, F, Args);
	_Else -> apply(gpio, F, Args)
    end.
