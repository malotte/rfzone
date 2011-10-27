%%%-------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2010, Tony Rogvall
%%% @doc
%%%     TELLSTICK command server
%%% @end
%%% Created :  1 Jul 2010 by Tony Rogvall <tony@rogvall.se>
%%%-------------------------------------------------------------------
-module(tellstick_drv).

-behaviour(gen_server).

%% API
-export([start/0, start/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

%% Remote control protocols
-export([nexa/3, nexax/3, waveman/3, sartano/2, ikea/4, risingsun/3]).

%% Testing
-export([test/0, run_test/1]).
-define(SERVER, ?MODULE). 

-ifdef(debug).
-define(dbg(Fmt,As), io:format((Fmt), (As))).
-else.
-define(dbg(Fmt,As), ok).
-endif.

-record(state, 
	{
	  sl,           %% serial port descriptor
	  device_name   %% device string
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

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @spec start() -> {ok, Pid} | ignore | {error, Error}
%% @doc
%% Starts the server.
%%
%% @end
%%--------------------------------------------------------------------
start() ->
    start([debug, {device,"/dev/tty.usbserial-A700eTGD"}]).

%%--------------------------------------------------------------------
%% @spec start(Ops) -> {ok, Pid} | ignore | {error, Error}
%% Opts = [{device, Device}]
%% Device = string() | simulated
%%
%% @doc
%% Starts the server.
%% Device contains the path to the Device. Default is "/dev/tty.usbserial-A700eTGD"
%%
%% @end
%%--------------------------------------------------------------------
start(Opts) ->
    gen_server:start({local,?SERVER}, ?MODULE, Opts, []).

%%--------------------------------------------------------------------
%% @spec nexa(House, Channel, On) -> ok | {error, Error}
%%   where
%%    House = integer()
%%    Channel = integer()
%%    On = boolean() | bell
%%
%% @doc
%% Sends a nexa protocol request to the device.
%% House should be in the range [$A - $P]. <br/>
%% Channel should be in the range [1 - 16]. <br/>
%%
%% @end
%%--------------------------------------------------------------------
nexa(House,Channel,On) when
      House >= $A, House =< $P,
      Channel >= 1, Channel =< 16, (is_boolean(On) orelse On=:=bell) ->
    gen_server:call(?SERVER, {nexa,House,Channel,On}).

%%--------------------------------------------------------------------
%% @spec nexax(Serial, Channel, Level) -> ok | {error, Error}
%%   where
%%    Serial = integer()
%%    Channel = integer()
%%    Level = boolean() | bell | integer()
%%
%% @doc
%% Sends a nexax protocol request to the device.
%% Serial should be in the range [0 - 16#3fffffff]. <br/>
%% Channel should be in the range [1 - 16]. <br/>
%% If Level is an integer it should be in the range [0 - 255]. <br/>
%%
%% @end
%%--------------------------------------------------------------------
nexax(Serial,Channel,Level) when
      Serial >= 0, Serial =< 16#3ffffff,
      Channel >= 1, Channel =< 16, 
      (is_boolean(Level) orelse (Level =:= bell) 
       orelse (is_integer(Level) andalso (Level >= 0)
	       andalso (Level =< 255))) ->
    gen_server:call(?SERVER, {nexax,Serial,Channel,Level}).

%%--------------------------------------------------------------------
%% @spec waveman(House, Channel, On) -> ok | {error, Error}
%%   where
%%    House = integer()
%%    Channel = integer()
%%    On = boolean() 
%%
%% @doc
%% Sends a waveman protocol request to the device.
%% House should be in the range [$A - $P]. <br/>
%% Channel should be in the range [1 - 16]. <br/>
%%
%% @end
%%--------------------------------------------------------------------
waveman(House,Channel,On) when
      House >= $A, House =< $P,
      Channel >= 1, Channel =< 16, is_boolean(On) ->
    gen_server:call(?SERVER, {waveman,House,Channel,On}).    

%%--------------------------------------------------------------------
%% @spec sartano(Channel, On) -> ok | {error, Error}
%%   where
%%    Channel = integer()
%%    On = boolean() 
%%
%% @doc
%% Sends a sartano protocol request to the device.
%% Channel should be in the range [1 - 16#3ff]. <br/>
%%
%% @end
%%--------------------------------------------------------------------
sartano(Channel,On) when
    Channel >= 0, Channel =< 16#3FF, is_boolean(On) ->
    gen_server:call(?SERVER, {sartano,Channel,On}).
    
%%--------------------------------------------------------------------
%% @spec ikea(system, Channel, Level, Style) -> ok | {error, Error}
%%   where
%%    Serial= integer()
%%    Channel = integer()
%%    Level = integer()
%%    Style = 0 | 1
%%
%% @doc
%% Sends a ikea protocol request to the device.
%% Serial should be in the range [1 - 16]. <br/>
%% Channel should be in the range [1 - 10]. <br/>
%% Level should be in the range [1 - 10]. <br/>
%%
%% @end
%%--------------------------------------------------------------------
ikea(System,Channel,Level,Style) when
      System >= 1, System =< 16,
      Channel >= 1, Channel =< 10,
      Level >= 0, Level =< 10,
      Style >= 0, Style =< 1 ->
    gen_server:call(?SERVER, {ikea,System,Channel,Level,Style}).
    
%%--------------------------------------------------------------------
%% @spec risingsun(Code, Unit, On) -> ok | {error, Error}
%%   where
%%    Code = integer()
%%    Unit = integer()
%%    On = boolean() 
%%
%% @doc
%% Sends a risingsun protocol request to the device.
%% Code should be in the range [1 - 4]. <br/>
%% Unit should be in the range [1 - 4]. <br/>
%%
%% @end
%%--------------------------------------------------------------------
risingsun(Code,Unit,On) when
      Code >= 1, Code =< 4, Unit >= 1, Unit =< 4, is_boolean(On) ->    
    gen_server:call(?SERVER, {risingsun,Code,Unit,On}).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @doc
%% Initializes the server
%%
%% @end
%%--------------------------------------------------------------------
init(Opts) ->
    DeviceName = case proplists:lookup(device, Opts) of
		     none ->
			 case os:getenv("TELLSTICK_DEVICE") of
			     false ->
				 "/dev/tty.usbserial";
			     Device -> Device
			 end;
		     {_,Device} -> Device
		 end,
    Speed = 4800,
    %% DOpts = [binary,{baud,Speed},{buftm,1},{bufsz,128},{csize,8},{stopb,1},{parity,0},{mode,raw}],
    case DeviceName of
	simulated -> 
	    ?dbg("TELLSTICK open: ~s\n", [DeviceName]),
	    S = #state { sl=DeviceName, 
			 device_name=DeviceName
		       },
	    {ok, S};
	_NotSimulated ->
	    case sl:open(DeviceName,[{baud,Speed}]) of
		{ok,SL} ->
		    ?dbg("TELLSTICK open: ~s@~w\n", [DeviceName,Speed]),
		    S = #state { sl=SL, 
				 device_name=DeviceName
			       },
		    {ok, S};
		Error ->
		    {stop, Error}
	    end
    end.


%%--------------------------------------------------------------------
%% @private
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
handle_call({nexa,House,Channel,On},_From,State) ->
    try nexa_command(House, Channel, On) of
	Command ->
	    Res = send_command(State#state.sl, Command),
	    {reply,Res, State}
    catch
	error:Reason ->
	    {reply, {error,Reason}, State}
    end;
handle_call({nexax,Serial,Channel,Level},_From,State) ->
    try nexax_command(Serial, Channel, Level) of
	Command ->
	    Res = send_command(State#state.sl, Command),
	    {reply,Res, State}
    catch
	error:Reason ->
	    {reply, {error,Reason}, State}
    end;
handle_call({waveman,House,Channel,On},_From,State) ->
    try waveman_command(House, Channel, On) of
	Command ->
	    Res = send_command(State#state.sl, Command),
	    {reply,Res, State}
    catch
	error:Reason ->
	    {reply, {error,Reason}, State}
    end;
handle_call({sartano,Channel,On},_From,State) ->
    try sartano_command(Channel, On) of
	Command ->
	    Res = send_command(State#state.sl, Command),
	    {reply,Res, State}
    catch
	error:Reason ->
	    {reply, {error,Reason}, State}
    end;
handle_call({ikea,System,Channel,Level,Style},_From,State) ->
    try ikea_command(System,Channel,Level,Style) of
	Command ->
	    Res = send_command(State#state.sl, Command),
	    {reply,Res, State}
    catch
	error:Reason ->
	    {reply, {error,Reason}, State}
    end;
handle_call({risingsun,Code,Unit,On},_From,State) ->
    try risingsun_command(Code,Unit, On) of
	Command ->
	    Res = send_command(State#state.sl, Command),
	    {reply,Res, State}
    catch
	error:Reason ->
	    {reply, {error,Reason}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error,bad_call}, State}.

%%--------------------------------------------------------------------
%% @private
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    io:format("Got cast: ~p\n",  [_Msg]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @doc
%% Handling all non call/cast messages
%%
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    io:format("Got info: ~p\n",  [_Info]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @spec terminate(Reason, State) -> void()
%%
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
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
%%% Internal functions
%%%===================================================================

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

waveman_command(HouseCode, Channel, On) ->
    nexa_command(HouseCode, Channel, On, true).

nexa_command(HouseCode, Channel, On) ->
    nexa_command(HouseCode, Channel, On, false).

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
ikea_command(System, Channel, DimLevel, DimStyle) when 
      System >= 1, System =< 16,
      Channel >= 1, Channel =< 10,
      DimLevel >= 0, DimLevel =< 10,
      DimStyle >= 0, DimStyle =< 1 ->
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


send_command(simulated, Data) ->
    io:format("~p: Sending data =~p\n", [?MODULE, Data]),
    ok;
send_command(SL, Data) ->
    Data1 = ascii_data(Data),
    N = length(Data1),
    Command = 
	if  N =< 60 ->
		[?TELLSTICK_SEND, Data1, ?TELLSTICK_END];
	    N =< 255 ->
		[?TELLSTICK_XSEND, xcommand(Data1), ?TELLSTICK_END]
	end,
    sl:send(SL, Command).

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
    io:format("T0=~w,T=~w,T2=~w,T3=~w,Np=~w\n", [U0,U1,U2,U3,Np]),
    [U0,U1,U2,U3,Np | bitstring_to_list(<<Bits/bits, 0:R>>)].

%%
%% TEST suite from telldus.suite (generated by rfcmd)
%%
test() ->
    File = filename:join(code:priv_dir(pds), "telldus.suite"),
    case file:consult(File) of
	{ok, Tests} ->
	    run_test(Tests);
	Error ->
	    Error
    end.

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
	    
