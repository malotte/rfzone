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
%%%     TELLSTICK driver.
%%%
%%% Created :  1 Jul 2010 by Tony Rogvall 
%%% @end
%%%-------------------------------------------------------------------
-module(tellstick_drv).

-behaviour(gen_server).

-include_lib("lager/include/log.hrl").

%% API
-export([start_link/1, 
	 stop/0,
	 subscribe/0,
	 subscribe/1,
	 unsubscribe/1,
	 change_device/1]).

%% Remote control protocols
-export([nexa/4, 
	 nexax/4, 
	 waveman/4, 
	 sartano/4, 
	 ikea/4, 
	 risingsun/4]).

%% gen_server callbacks
-export([init/1, 
	 handle_call/3, 
	 handle_cast/2, 
	 handle_info/2,
	 terminate/2, 
	 code_change/3]).

%% Applied functions
-export([nexa_command/3, 
	 nexax_command/3, 
	 waveman_command/3, 
	 sartano_command/2, 
	 ikea_command/4, 
	 risingsun_command/3]).

%% Testing
-export([start_link/0, 
	 test/0, 
	 run_test/1, 
	 debug/1,
	 version/0,
	 setopt/1,
	 command/1]).

-define(SERVER, ?MODULE). 

-record(subscription,
	{
	  pid,
	  mon,
	  pattern
	}).

-record(ctx, 
	{
	  uart,           %% serial port descriptor
	  device,         %% device string
	  variant,        %% stick/duo/net | v1|v2|v3|simulated
	  version,        %% tellstick(duo) version
	  command,        %% last command
	  client,         %% last client
	  queue,          %% request queue
	  reply_timer,    %% timeout waiting for reply
	  reopen_ival,    %% interval betweem open retry 
	  reopen_timer,   %% timer ref
	  subs = [],      %% #subscription{}
	  trace           %% debug tracing
	}).

-define(TELLSTICK_SEND,  $S).       %% param byte...
-define(TELLSTICK_XSEND, $T).       %% t1,t2,t3,t4,<n>,<bits>
-define(TELLSTICK_VSN,   $V).
-define(TELLSTICK_END,   $+).

-define(PFX_TELLSTICK_DEBUG, $D).   %% set debug...(test me)
-define(PFX_TELLSTICK_PAUSE, $P).   %% param (byte) ms
-define(PFX_TELLSTICK_REPEAT, $R).  %% param (byte) repeat count

-define(ASCII_TO_US(C), ((C)*10)).
%% We should probably 430 separatly (it's a + sign!)
-define(US_TO_ASCII(U), ((U) div 10)).

%% For dialyzer
-type start_options()::{device, {Device::string() | simulated, v1 | v2}} |
		       {retry_timeout, TimeOut::timeout()} |
		       {debug, TrueOrFalse::boolean()}.


%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server.
%%
%% Device contains the path to the Device and the version. <br/>
%% Timeout =/= 0 means that if the driver fails to open the device it
%% will try again in Timeout seconds.<br/>
%% Debug controls trace output.<br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec start_link(list(Options::start_options())) -> 
		   {ok, Pid::pid()} | 
		   ignore | 
		   {error, Error::term()}.

start_link(Opts) ->
    lager:info("~p: start_link: args = ~p\n", [?MODULE, Opts]),
    gen_server:start_link({local,?SERVER}, ?MODULE, Opts, []).

%%--------------------------------------------------------------------
%% @doc
%% Stops the server.
%%
%% @end
%%--------------------------------------------------------------------
-spec stop() -> ok | {error, Error::term()}.

stop() ->
    gen_server:call(?SERVER, stop).


%%--------------------------------------------------------------------
%% @doc
%% Subscribe to telldus (duo) events.
%%
%% @end
%%--------------------------------------------------------------------
-spec subscribe(Pattern::[{atom(),string()}]) ->
		       {ok,reference()} | {error, Error::term()}.
subscribe(Pattern) ->
    gen_server:call(?SERVER, {subscribe,self(),Pattern}).


%%--------------------------------------------------------------------
%% @doc
%% Subscribe to telldus (duo) events.
%%
%% @end
%%--------------------------------------------------------------------
-spec subscribe() -> {ok,reference()} | {error, Error::term()}.
subscribe() ->
    gen_server:call(?SERVER, {subscribe,self(),[]}).

%%--------------------------------------------------------------------
%% @doc
%% Unsubscribe from telldus (duo) events.
%%
%% @end
%%--------------------------------------------------------------------
-spec unsubscribe(Ref::reference()) -> ok | {error, Error::term()}.
unsubscribe(Ref) ->
    gen_server:call(?SERVER, {unsubscribe,Ref}).

%%--------------------------------------------------------------------
%% @doc
%% Changes device.
%%
%% @end
%%--------------------------------------------------------------------
-spec change_device({DeviceName::string(), Version::atom()}) -> 
			   ok | {error, Error::term()}.

change_device(NewDevice) ->
    gen_server:call(?SERVER, {change_device, NewDevice}).

%%--------------------------------------------------------------------
%% @doc
%% Sends a nexa protocol request to the device.<br/>
%% House should be in the range [$A - $P]. <br/>
%% Channel should be in the range [1 - 16]. <br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec nexa(House::integer(), 
	   Channel::integer(), 
	   On::boolean() | bell,
	   []) -> 
		  ok | {error, Error::term()}.

nexa(House,Channel,On,[]) when
      House >= $A, House =< $P,
      Channel >= 1, Channel =< 16, (is_boolean(On) orelse On=:=bell) ->
    gen_server:call(?SERVER, {nexa,House,Channel,On}, 9000).

%%--------------------------------------------------------------------
%% @doc
%% Sends a nexax protocol request to the device.
%% Serial should be in the range [0 - 16#3fffffff]. <br/>
%% Channel should be in the range [1 - 16]. <br/>
%% If Level is an integer it should be in the range [0 - 255]. <br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec nexax(Serial::integer(), 
	    Channel::integer(), 
	    Level::boolean() | bell | integer(),
	    list(term())) -> 
		   ok | {error, Error::term()}.

nexax(Serial,Channel,Level,_Flags) when
      Serial >= 0, Serial =< 16#3ffffff,
      Channel >= 1, Channel =< 16, 
      (is_boolean(Level) orelse (Level =:= bell) 
       orelse (is_integer(Level) andalso (Level >= 0)
	       andalso (Level =< 255))) ->
    gen_server:call(?SERVER, {nexax,Serial,Channel,Level}, 9000).

%%--------------------------------------------------------------------
%% @doc
%% Sends a waveman protocol request to the device.<br/>
%% House should be in the range [$A - $P]. <br/>
%% Channel should be in the range [1 - 16]. <br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec waveman(House::integer(), 
	      Channel::integer(), 
	      On::boolean(),
	      []) -> 
		     ok | {error, Error::term()}.

waveman(House,Channel,On,[]) when
      House >= $A, House =< $P,
      Channel >= 1, Channel =< 16, is_boolean(On) ->
    gen_server:call(?SERVER, {waveman,House,Channel,On}, 9000).    

%%--------------------------------------------------------------------
%% @doc
%% Sends a sartano protocol request to the device.<br/>
%% Channel should be in the range [1 - 16#3ff]. <br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec sartano(Dummy::term(),
	      Channel::integer(), 
	      On::boolean(),
	      []) -> 
		     ok | {error, Error::term()}.

sartano(_Dummy,Channel,On,[]) when
    Channel >= 0, Channel =< 16#3FF, is_boolean(On) ->
    gen_server:call(?SERVER, {sartano,Channel,On}, 9000).
    
%%--------------------------------------------------------------------
%% @doc
%% Sends a ikea protocol request to the device.<br/>
%% Serial should be in the range [1 - 16]. <br/>
%% Channel should be in the range [1 - 10]. <br/>
%% Level should be in the range [0 - 10]. <br/>
%% Flags should be [{style, smooth | instant}]. <br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec ikea(System::integer(), 
	   Channel::integer(), 
	   Level::integer(), 
	   Flags::list({style, Style:: smooth | instant})) -> 
		  ok | {error, Error::term()}.

ikea(System,Channel,Level,Flags) when
      System >= 1, System =< 16,
      Channel >= 1, Channel =< 10,
      Level >= 0, Level =< 10,
      is_list(Flags) ->
    DimStyle = 
	case proplists:get_value(style, Flags, smooth) of
	    smooth -> 1;
	    instant -> 0
	end,
    gen_server:call(?SERVER, {ikea,System,Channel,Level,DimStyle}, 9000).
    
%%--------------------------------------------------------------------
%% @doc
%% Sends a risingsun protocol request to the device.<br/>
%% Code should be in the range [1 - 4]. <br/>
%% Unit should be in the range [1 - 4]. <br/>
%%
%% @end
%%--------------------------------------------------------------------
-spec risingsun(Code::integer(), 
		Unit::integer(), 
		On::boolean(),
		[]) -> 
		       ok | {error, Error::term()}.

risingsun(Code,Unit,On,[]) when
      Code >= 1, Code =< 4, Unit >= 1, Unit =< 4, is_boolean(On) ->    
    gen_server:call(?SERVER, {risingsun,Code,Unit,On}, 9000).


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Starts the server with default values.
%% Default for Device is "/dev/tty.usbserial-A700eTGD"
%%
%% @end
%%--------------------------------------------------------------------
-spec start_link() -> 
		   {ok, Pid::pid()} | ignore | {error, Error::term()}.

start_link() ->
    start_link([{debug, true}, {device,{"/dev/tty.usbserial-A900I902", v1}}]).

%% @private
debug(TrueOrFalse) when is_boolean(TrueOrFalse) ->
    gen_server:call(?SERVER, {debug, TrueOrFalse}).

version() ->
    gen_server:call(?SERVER, version).

%% @private
setopt(O={_Option, _Value}) ->
    gen_server:cast(?SERVER, {setopt, O}).

%% @private
command(C) ->
    gen_server:cast(?SERVER, {command,C}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
%%--------------------------------------------------------------------
%% @doc
%% Initializes the server
%%
%% @end
%%--------------------------------------------------------------------
-spec init(list(Options::start_options())) -> 
		  {ok, Ctx::#ctx{}} |
		  {ok, Ctx::#ctx{}, Timeout::timeout()} |
		  ignore |
		  {stop, Reason::term()}.

init(Opts) ->
    {ok,Trace} = set_trace(proplists:get_bool(debug, Opts), undefined),
    lager:info("~p: init: args = ~p,\n pid = ~p\n", [?MODULE, Opts, self()]),
    {Device,Variant} = 
	case proplists:lookup(device, Opts) of
	    none ->
		case os:getenv("TELLSTICK_DEVICE") of
		    false -> {"",v1};
		    EnvDevice -> {EnvDevice, v1}
		end;
	    {device,PropDev} when is_list(PropDev) -> {PropDev,v1};
	    {device,Dev={DeviceName,v1}} when is_list(DeviceName) -> Dev;
	    {device,Dev={DeviceName,v2}} when is_list(DeviceName) -> Dev;
	    {device,{simulated,v1}} -> {"",v1};
	    {device,{simulated,v2}} -> {"",v2}
	end,
    Reopen_ival = proplists:get_value(retry_timeout, Opts, infinity),
    S = #ctx { device = Device, 
	       variant=Variant,
	       reopen_ival = Reopen_ival,
	       queue = queue:new(),
	       trace = Trace },
    case open(S) of
	{ok, S1} -> {ok, S1};
	Error -> {stop, Error}
    end.
	    
open(Ctx=#ctx {device = ""}) ->
    lager:debug("TELLSTICK open: simulated\n", []),
    {ok, Ctx#ctx { uart=simulated, version="0" }};

open(Ctx=#ctx {device = DeviceName, variant=Variant,
	       reopen_ival = Reopen_ival }) ->
    Speed = case Variant of
		v1 -> 4800; %% Only 4800 possible for tellstick v1 ...
		v2 -> 9600
	    end,
    Options = [{baud,Speed},{mode,list},{active,true},{packet,line},
	       {csize,8},{parity,none},{stopb,1}],
    case uart:open(DeviceName,Options) of
	{ok,U} ->
	    lager:debug("TELLSTICK open: ~s@~w -> ~p", [DeviceName,Speed,U]),
	    uart:send(U, "V+"), %% answer is picked in handle_info
	    {ok, Ctx#ctx { uart=U }};
	{error, E} when E == eaccess;
			E == enoent ->
	    if Reopen_ival == infinity ->
		    lager:debug("open: Driver not started, reason = ~p.\n", [E]),
		    {error, E};
	       true ->
		    lager:debug("open: Port could not be opened, will try again "
			 "in ~p millisecs.\n", [Reopen_ival]),
		    Reopen_timer = erlang:start_timer(Reopen_ival,
						      self(), open_device),
		    {ok, Ctx#ctx { reopen_timer = Reopen_timer }}
	    end;
	    
	Error ->
	    lager:debug("open: Driver not started, reason = ~p.\n", 
		 [Error]),
	    Error
    end.

close(Ctx=#ctx {uart = U}) when is_port(U) ->
    lager:debug("TELLSTICK close: ~p", [U]),
    uart:close(U),
    {ok, Ctx#ctx { uart=undefined }};
close(Ctx) ->
    {ok, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-type call_request()::
	{nexa, House::integer(), Channel::integer(), On::boolean() | bell} |
	{nexax, Serial::integer(), Channel::integer(), Level::boolean() | bell | integer()} |
	{waveman, House::integer(), Channel::integer(), On::boolean()} |
	{sartano, Channel::integer(), On::boolean()} |
	{ikea, System::integer(), Channel::integer(), Level::integer(), Style:: 0 | 1} |
	{risingsun, Code::integer(), Unit::integer(), On::boolean()} |
	{change_device, {DeviceName::string(), Version::atom()}} |
	{debug, TrueOrFalse::boolean()} |
	stop.

-spec handle_call(Request::call_request(), From::{pid(), Tag::term()}, Ctx::#ctx{}) ->
			 {reply, Reply::term(), Ctx::#ctx{}} |
			 {noreply, Ctx::#ctx{}} |
			 {stop, Reason::atom(), Reply::term(), Ctx::#ctx{}}.

handle_call({subscribe,Pid,Pattern},_From,Ctx=#ctx { subs=Subs}) ->
    Mon = erlang:monitor(process, Pid),
    Subs1 = [#subscription { pid = Pid, mon = Mon, pattern = Pattern}|Subs],
    {reply, {ok,Mon}, Ctx#ctx { subs = Subs1}};

handle_call({unsubscribe,Ref},_From,Ctx) ->
    erlang:demonitor(Ref),
    Ctx1 = remove_subscription(Ref,Ctx),
    {reply, ok, Ctx1};
    
handle_call(version, _From, Ctx) ->
    if Ctx#ctx.uart =:= undefined ->
	    {reply, {error,no_port}, Ctx};
       true ->
	    {reply, Ctx#ctx.version, Ctx}
    end;

handle_call(Call,From,Ctx=#ctx {client = Client}) 
  when Client =/= undefined andalso Call =/= stop ->
    %% Driver is busy ..
    lager:debug("handle_call: Driver busy, store call ~p", [Call]),
    %% set timer already here? probably!
    Q = queue:in({call,Call,From}, Ctx#ctx.queue),
    {noreply, Ctx#ctx { queue = Q }};

handle_call({nexa,House,Channel,On},From,Ctx) ->
    command(nexa_command,[House, Channel, On], Ctx#ctx {client = From});
handle_call({nexax,Serial,Channel,Level},From,Ctx) ->
     command(nexax_command, [Serial, Channel, Level], Ctx#ctx {client = From});
handle_call({waveman,House,Channel,On},From,Ctx) ->
    command(waveman_command, [House, Channel, On], Ctx#ctx {client = From});
handle_call({sartano,Channel,On},From,Ctx) ->
    command(sartano_command,[Channel, On], Ctx#ctx {client = From});
handle_call({ikea,System,Channel,Level,Style},From,Ctx) ->
    command(ikea_command, [System,Channel,Level,Style], Ctx#ctx {client = From});
handle_call({risingsun,Code,Unit,On},From,Ctx) ->
    command(risingsun_command, [Code,Unit,On], Ctx#ctx {client = From});

handle_call({change_device, Device={_DeviceName, _Version}}, _From, Ctx) ->
    lager:debug("handle_call: change device to ~p", [Device]),
    close(Ctx),
    case open(Ctx#ctx {device = Device}) of
	{ok, Ctx1} ->
	     {reply, ok, Ctx1};
	Error ->
	    {reply, Error, Ctx}
    end;

handle_call({debug, On}, _From, Ctx) ->
    case set_trace(On, Ctx#ctx.trace) of
	{ok,Trace} ->
	    {reply, ok, Ctx#ctx { trace = Trace }};
	Error ->
	    {reply, Error, Ctx}
    end;

handle_call(stop, _From, Ctx) ->
    {stop, normal, ok, Ctx};

handle_call(_Request, _From, Ctx) ->
    {reply, {error,bad_call}, Ctx}.


command(F, Args, Ctx=#ctx {uart = U, client = _Client}) when U =/= undefined ->
    try apply(?MODULE, F, Args) of
	PulseData ->
	    case send_command(U, PulseData) of
		{ok,Command1} ->
		    lager:debug("command: sent ~p, client ~p", 
			 [Command1,_Client]),
		    %% Wait for confirmation
		    TRef = erlang:start_timer(3000, self(), reply),
		    {noreply,Ctx#ctx {command = Command1, reply_timer = TRef}};
		{simulated, ok} ->
		    {reply, ok, Ctx};
		Other ->
		    lager:debug("command: send failed, reason ~p", [Other]),
		    {reply, Other, Ctx}
	    end
    catch
	error:Reason ->
	    {reply, {error,Reason}, Ctx}
    end;
command(_F, _Args, Ctx) ->
    lager:info("~p: No port defined yet.\n", [?MODULE]),
    {reply, {error,no_port}, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_cast(Msg::term(), Ctx::#ctx{}) -> 
			 {noreply, Ctx::#ctx{}} |
			 {stop, Reason::term(), Ctx::#ctx{}}.

handle_cast({setopt, {Option, Value}}, Ctx=#ctx { uart = U}) ->
    lager:debug("handle_cast: setopt ~p = ~p", [Option, Value]),
    uart:setopt(U, Option, Value),
    {noreply, Ctx};
handle_cast(Cast, Ctx=#ctx {uart = U, client=Client})
  when U =/= undefined, Client =/= undefined ->
    lager:debug("handle_cast: Driver busy, store cast ~p", [Cast]),
    Q = queue:in({cast,Cast}, Ctx#ctx.queue),
    {noreply, Ctx#ctx { queue = Q }};
handle_cast({command, Command}, Ctx=#ctx {uart = U}) ->
    lager:debug("handle_cast: command ~p", [Command]),
    _Reply = uart:send(U, Command),
    lager:debug("handle_cast: command reply ~p", [_Reply]),
    {noreply, Ctx};
handle_cast(_Msg, Ctx) ->
    lager:debug("handle_cast: Unknown message ~p", [_Msg]),
    {noreply, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @end
%%--------------------------------------------------------------------
-type info()::
	retry |
	{Port::term(), {data, Data::binary()}} |
	term() .

-spec handle_info(Info::info(), Ctx::#ctx{}) -> 
			 {noreply, Ctx::#ctx{}} |
			 {stop, Reason::term(), Ctx::#ctx{}}.

handle_info(retry, Ctx) ->
    lager:debug("handle_info: retry open port", []),
    case open(Ctx) of
	{ok, Ctx1} -> {noreply, Ctx1};
	Error -> {stop, Error, Ctx}
    end;
handle_info({timeout,TRef,reply}, 
	    Ctx=#ctx {client=Client, reply_timer=TRef}) ->
    lager:debug("handle_info: timeout waiting for port", []),
    gen_server:reply(Client, {error, port_timeout}),
    Ctx1 = Ctx#ctx { reply_timer=undefined, client = undefined},
    next_command(Ctx1);

handle_info({uart,U,Data},  Ctx) when U =:= Ctx#ctx.uart ->
    lager:debug("handle_info: port data ~p", [Data]),
    case trim(Data) of
	[$+,CmdChar|_CmdReply] when Ctx#ctx.client =/= undefined, 
				   CmdChar =:= hd(Ctx#ctx.command) ->
	    erlang:cancel_timer(Ctx#ctx.reply_timer),
	    gen_server:reply(Ctx#ctx.client, ok),
	    Ctx1 = Ctx#ctx { client=undefined, reply_timer=undefined,
			     command = "" },
	    next_command(Ctx1);
	[$+,$V|Vsn] -> 
	    {noreply, Ctx#ctx { version = Vsn }};
	[$+,$W|EventData] ->
	    Ctx1 = event_notify(EventData, Ctx),
	    {noreply, Ctx1};
	_ ->
	    lager:debug("handle_info: reply ~p", [Data]),
	    {noreply, Ctx}
    end;
handle_info({uart_error,U,Reason}, Ctx) when U =:= Ctx#ctx.uart ->
    if Reason =:= enxio ->
	    lager:error("uart error ~p device ~s unplugged?", 
			[Reason,Ctx#ctx.device]);
       true ->
	    lager:error("uart error ~p for device ~s", 
			[Reason,Ctx#ctx.device])
    end,
    {noreply, Ctx};
handle_info({uart_closed,U}, Ctx) when U =:= Ctx#ctx.uart ->
    uart:close(U),
    lager:error("uart close device ~s will retry", [Ctx#ctx.device]),
    Reopen_timer = erlang:start_timer(Ctx#ctx.reopen_ival,
				      self(), open_device),
    {noreply, Ctx#ctx { uart=undefined,reopen_timer = Reopen_timer }};

handle_info({timeout,Ref,open_device}, Ctx) when Ctx#ctx.reopen_timer =:= Ref ->
    Ctx1 = open(Ctx#ctx { reopen_timer = undefined} ),
    {noreply, Ctx1};

handle_info({'DOWN',Ref,process,_Pid,_Reason},Ctx) ->
    lager:debug("handle_info: subscriber ~p terminated: ~p", 
	 [_Pid, _Reason]),
    Ctx1 = remove_subscription(Ref,Ctx),
    {noreply, Ctx1};
handle_info(_Info, Ctx) ->
    lager:debug("handle_info: Unknown info ~p", [_Info]),
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
-spec terminate(Reason::term(), Ctx::#ctx{}) -> 
		       ok.

terminate(_Reason, Ctx) ->
    stop_trace(Ctx#ctx.trace),
    close(Ctx),
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


next_command(Ctx) ->
    case queue:out(Ctx#ctx.queue) of
	{{value,{call,Call,From}}, Q1} ->
	    case handle_call(Call, From, Ctx#ctx { queue=Q1}) of
		{reply,Reply,Ctx1} ->
		    gen_server:reply(From,Reply),
		    {noreply,Ctx1};
		CallResult ->
		    CallResult
	    end;
	{{value,{cast,Cast}}, Q1} ->
	    handle_cast(Cast, Ctx#ctx { queue=Q1});
	{empty, Q1} ->
	    {noreply, Ctx#ctx { queue=Q1}}
    end.
	    
trim([0|Cs])   -> trim(Cs);  %% check this, sometimes 0's occure in the stream
trim([$\s|Cs]) -> trim(Cs);
trim([$\t|Cs]) -> trim(Cs);
trim(Cs) -> trim_end(Cs).

trim_end([$\r,$\n]) -> [];
trim_end([$\n]) -> [];
trim_end([$\r]) -> [];
trim_end([]) -> [];
trim_end([C|Cs]) -> [C|trim_end(Cs)].

remove_subscription(Ref, Ctx=#ctx { subs=Subs}) ->
    Subs1 = lists:keydelete(Ref, #subscription.mon, Subs),
    Ctx#ctx { subs = Subs1 }.
    

event_notify(String, Ctx) ->
    Event = 
	[ case string:tokens(D, ":") of
	      ["data",Data="0x"++Value] ->
		  try list_to_integer(Value,16) of
		      V -> {data, V}
		  catch
		      error:Error ->  
		          lager:error("unable to convert ~p to integer:~p\n",
                                      [Data, Error]),
			  {data,Data}
		  end;
	      [K,V] ->
		  {list_to_atom(K), V};
	      [K] ->

	          {undefined, K}
	  end || D <- string:tokens(String, ";")],
    send_event(Ctx#ctx.subs, Event),
    %% send to event listener(s)
    io:format("Event: ~p\n", [Event]),
    Ctx.

send_event([#subscription{pid=Pid,mon=Ref,pattern=Pattern}|Tail], Event) ->
    case match_event(Pattern, Event) of
	true -> Pid ! {tellstick_event,Ref,Event};
	false -> false
    end,
    send_event(Tail,Event);
send_event([],_Event) ->
    ok.

match_event([], _) -> true;
match_event([{Key,ValuePat}|Kvs],Event) ->
    case lists:keyfind(Key, 1, Event) of
	{Key,ValuePat} -> match_event(Kvs, Event);
	_ -> false
    end.


-define(NEXA_0, [320,960,320,960]).  %% zero bit
-define(NEXA_1, [960,320,960,320]).  %% one bit  (not used?)
-define(NEXA_X, [320,960,960,320]).  %% open bit
-define(NEXA_S, [320,1250]).         %% sync bit

-define(NEXA_ON_BIT,  16#800).
-define(NEXA_BIT_4,   16#400). %% ?
-define(NEXA_BIT_2,   16#200). %% ?
-define(NEXA_BIT_1,   16#100). %% ?

-define(NEXA_BELL,   16#F00).
-define(NEXA_ON,     16#E00).
-define(NEXA_OFF,    16#600).
-define(WAVEMAN_OFF, 16#000).

%% @private
waveman_command(HouseCode, Channel, On) ->
    nexa_command(HouseCode, Channel, On, true).

%% @private
nexa_command(HouseCode, Channel, On) ->
    nexa_command(HouseCode, Channel, On, false).

%% @private
nexa_command(HouseCode, Channel, On, WaveMan) when
      HouseCode >= $A, HouseCode =< $P,
      Channel >= 1, Channel =< 16, (is_boolean(On) orelse On =:= bell) ->
    Channel1 = if On =:= bell -> 7;
		  true -> Channel - 1
	       end,
    TxCode0 = (Channel1 bsl 4) bor (HouseCode-$A),
    TxCode = if  On =:= bell ->
		     TxCode0 bor ?NEXA_BELL;
		 On =:= true ->
		     TxCode0 bor ?NEXA_ON;
		WaveMan, On =:= false ->
		     TxCode0 bor ?WAVEMAN_OFF;
		true ->
		     TxCode0 bor ?NEXA_OFF
	     end,
    nexa_rf_code(TxCode, 12) ++ ?NEXA_S.

nexa_rf_code(Code, N) ->
    rf_code_lh(Code, N, ?NEXA_0, ?NEXA_X). 

-define(T00, 1270).
-define(T01, 2550).
-define(T10, 240).
-define(T11, 10).

-define(NEXAX_0, [?T10,?T10,?T10,?T00]).  %% zero bit
-define(NEXAX_1, [?T10,?T00,?T10,?T10]).  %% open bit
-define(NEXAX_D, [?T10,?T10,?T10,?T10]).  %% one bit
-define(NEXAX_S, [?T10,?T01]).            %% start bit
-define(NEXAX_P, [?T10]).                 %% pad?

%%  "1" => 1000 = [240,1270]
%%  "0" => 1010 = [240,240]
%%  X  ==  "10" => 10001010 = [240,1270,240,240]
%%  Z  == "01" => 10101000 = [240,240,240,1270]
%%  1  == "00" => 10101010 = [240,240,240,240]
%%  "11" => not used

%% @private
nexax_command(Serial, Channel, Level) when
      Serial >= 0, Serial =< 16#3ffffff,
      Channel >= 1, Channel =< 16, 
      (is_boolean(Level) orelse (Level =:= bell) 
       orelse (is_integer(Level) andalso (Level >= 0)
	       andalso (Level =< 255))) ->
    Channel1 = if Level =:= bell -> 7;
		  true -> Channel - 1
	       end,
    ?NEXAX_S ++
    nexax_rf_code(Serial, 26) ++
	?NEXAX_0 ++  %% Group
	if is_integer(Level) ->
		?NEXAX_D;
	   Level =:= false ->
		?NEXAX_0;
	   Level =:= true ->
		?NEXAX_1;
	   Level =:= bell ->
		?NEXAX_1
	end ++
	nexax_rf_code(Channel1, 4) ++
	if is_integer(Level) ->
		nexax_rf_code(Level div 16, 4) ++
		    ?NEXAX_P;
	   true ->
		?NEXAX_P
	end.
    
nexax_rf_code(Code, N) ->      
    rf_code_hl(Code, N, ?NEXAX_0, ?NEXAX_1). 
    


-define(SARTANO_0, [360,1070,1070,360]). %% $kk$
-define(SARTANO_1, [360,1070,360,1070]). %% $k$k
-define(SARTANO_X, []).
-define(SARTANO_S, [360,1070]).  %% $k

%% @private
sartano_command(Channel, On) when
      Channel >= 1, Channel =< 10, is_boolean(On) ->
    sartano_multi_command((1 bsl (Channel-1)), On).

%% Hmm high bit is first channel?
sartano_multi_command(ChannelMask, On) when
      ChannelMask >= 0, ChannelMask =< 16#3FF, is_boolean(On) ->
    ChannelBits = reverse_bits(ChannelMask, 10),
    if On ->
	    sartano_rf_code(ChannelBits,10) ++
		sartano_rf_code(2#01, 2) ++ ?SARTANO_S;
       true ->
	    sartano_rf_code(ChannelBits,10) ++ 
		sartano_rf_code(2#10, 2) ++ ?SARTANO_S
    end.

sartano_rf_code(Code, N) ->
    rf_code_lh(Code, N, ?SARTANO_0, ?SARTANO_1).

		
-define(IKEA_0, [1700]).    %% high or low 
-define(IKEA_1, [840,840]). %% toggle  TT
%%
%% Looks like channel code is a bit mask!!! multiple channels at once!!!?
%% Note: this is normalized to send b0 first!
%% DimStyle: 0  Instant
%%         : 1  Smooth
%%
%% @private
ikea_command(System, Channel, DimLevel, DimStyle) when 
      System >= 1, System =< 16 andalso
      Channel >= 1, Channel =< 10 andalso
      DimLevel >= 0, DimLevel =< 10 andalso
      (DimStyle == 0 orelse DimStyle == 1) ->
    ChannelCode = Channel rem 10,
    IntCode0 = (1 bsl (ChannelCode+4)) bor reverse_bits(System-1,4),
    IntFade = (DimStyle*2 + 1) bsl 4,   %% 1 or 3 bsl 4
    IntCode1 = if DimLevel =:= 0 ->  10 bor IntFade;
		  DimLevel =:= 10 -> 0 bor IntFade;
		  true -> DimLevel bor IntFade
	       end,
    ikea_rf_code(2#0111, 4) ++
	ikea_rf_code(IntCode0, 14) ++
	ikea_rf_code(checksum_bits(IntCode0, 14), 2) ++
	ikea_rf_code(IntCode1, 6) ++
	ikea_rf_code(checksum_bits(IntCode1, 6), 2).

%% Low to high bits
ikea_rf_code(Code, N) ->
    rf_code_lh(Code, N, ?IKEA_0, ?IKEA_1).

%% Two bit toggle checksum 
checksum_bits(Bits, N) ->
    checksum_bits(Bits, N, 0).

checksum_bits(_Bits, I, CSum) when I =< 0 -> 
    CSum bxor 3;  %% invert
checksum_bits(Bits, I, CSum) ->
    checksum_bits(Bits bsr 2, I-2, CSum bxor (Bits band 3)).

    
-define(RISING_0, [1010, 460, 460, 1010]).  %% e..e
-define(RISING_1, [460, 1010, 460, 1010]).  %% .e.e
-define(RISING_S, [460, 1010]).
%%
%% I guess that rising sun can send bit patterns on both code and unit
%% This is coded for one code/unit only
%%
%% @private
risingsun_command(Code, Unit, On) when
      Code >= 1, Code =< 4, Unit >= 1, Unit =< 4, is_boolean(On) ->
    risingsun_multi_command((1 bsl (Code-1)), (1 bsl (Unit-1)), On).

risingsun_multi_command(Codes, Units, On) when
      Codes >= 0, Codes =< 15, Units >= 0, Units =< 15, is_boolean(On) ->
    ?RISING_S ++ 
	risingsun_rf_code(Codes,4) ++
	risingsun_rf_code(Units,4) ++
	if On ->
		risingsun_rf_code(2#0000, 4);
	   true ->
		risingsun_rf_code(2#1000, 4)
	end.

risingsun_rf_code(Code, N) ->
    rf_code_lh(Code, N, ?RISING_0, ?RISING_1).


%% rf_code_lh build send list b(0) ... b(n-1)
rf_code_lh(_Bits, 0, _B0, _B1) ->  
    [];
rf_code_lh(Bits, I, B0, B1) ->
    if Bits band 1 =:= 1 ->
	    B1 ++ rf_code_lh(Bits bsr 1, I-1, B0, B1);
       true ->
	    B0 ++ rf_code_lh(Bits bsr 1, I-1, B0, B1)
    end.

%% rf_code_hl build send list b(n-1) ... b(0)
rf_code_hl(_Code, 0, _B0, _B1) ->
    [];
rf_code_hl(Code, I, B0, B1) ->
    if Code band 1 =:= 1 ->
	    rf_code_hl(Code bsr 1, I-1, B0, B1) ++ B1;
       true ->
	    rf_code_hl(Code bsr 1, I-1, B0, B1) ++ B0
    end.

%% reverse N bits
reverse_bits(Bits, N) ->
    reverse_bits_(Bits, N, 0).

reverse_bits_(_Bits, 0, RBits) ->
    RBits;
reverse_bits_(Bits, I, RBits) ->
    reverse_bits_(Bits bsr 1, I-1, (RBits bsl 1) bor (Bits band 1)).


send_command(simulated, _Data) ->
    lager:debug("send_command: Sending data =~p\n", [_Data]),
    {simulated, ok};
send_command(U, Data) ->
    Data1 = ascii_data(Data),
    N = length(Data1),
    Command = 
	if  N =< 60 ->
		[?TELLSTICK_SEND, Data1, ?TELLSTICK_END];
	    N =< 255 ->
		[?TELLSTICK_XSEND, xcommand(Data1), ?TELLSTICK_END]
	end,
    Res = uart:send(U, Command),
    {Res, Command}.


ascii_data(Data) ->
    [ ?US_TO_ASCII(T) || T <- lists:flatten(Data) ].

%% Compress the data if possible!!!
xcommand(Data) ->
    xcommand(Data,0,0,0,0,<<>>).

xcommand([T|Data],T0,T1,T2,T3,Bits) ->
    if T =:= T0 ->
	    xcommand(Data,T0,T1,T2,T3,<<Bits/bits,00:2>>);
       T =:= T1 ->
	    xcommand(Data,T0,T1,T2,T3,<<Bits/bits,01:2>>);
       T =:= T2 ->
	    xcommand(Data,T0,T1,T2,T3,<<Bits/bits,10:2>>);
       T =:= T3 ->
	    xcommand(Data,T0,T1,T2,T3,<<Bits/bits,11:2>>);
       T0 =:= 0 ->
	    xcommand(Data,T,T1,T2,T3,<<Bits/bits,00:2>>);
       T1 =:= 0 ->
	    xcommand(Data,T0,T,T2,T3,<<Bits/bits,01:2>>);
       T2 =:= 0 ->
	    xcommand(Data,T0,T1,T,T3,<<Bits/bits,10:2>>);
       T3 =:= 0 ->
	    xcommand(Data,T0,T1,T2,T,<<Bits/bits,11:2>>)
    end;
xcommand([],T0,T1,T2,T3,Bits) ->
    Sz = bit_size(Bits),
    Np = Sz div 2,        %% number of pulses
    Nb = (Sz + 7) div 8,  %% number of bytes
    R = Nb*8 - Sz,        %% pad bits
    U0 = if T0 =:= 0 -> 1; true -> T0 end,
    U1 = if T1 =:= 0 -> 1; true -> T1 end,
    U2 = if T2 =:= 0 -> 1; true -> T2 end,
    U3 = if T3 =:= 0 -> 1; true -> T3 end,
    lager:debug("xcommand: T0=~w,T=~w,T2=~w,T3=~w,Np=~w\n", [U0,U1,U2,U3,Np]),
    [U0,U1,U2,U3,Np | bitstring_to_list(<<Bits/bits, 0:R>>)].

%%
%% TEST suite from telldus.suite (generated by rfcmd)
%% @private
test() ->
    File = filename:join(code:priv_dir(rfzone), "telldus.suite"),
    case file:consult(File) of
	{ok, Tests} ->
	    run_test(Tests);
	Error ->
	    Error
    end.

%% @private
run_test([]) ->
    ok;
run_test([{Prod,Args,Result} | Test]) ->
    io:format("Test: ~p args=~w\n", [Prod, Args]),
    Func = list_to_atom(atom_to_list(Prod)++"_command"),
    try apply(?MODULE, Func, Args) of
	Result -> 
	    io:format("OK\n"),
	    run_test(Test);
	_BadResult ->
	    io:format("Error:\n"),
	    io:format("    Wanted: ~w\n", [Result]),
	    io:format(" Generated: ~w\n", [_BadResult]),
	    run_test(Test)
    catch 
	error:Reason ->
	    io:format("Error:\n"),
	    io:format(" Crash: ~p\n", [Reason]),
	    run_test(Test)
    end.
	    
