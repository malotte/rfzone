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
%%% @author Malotte Westman Lönne <malotte@malotte.net>
%%% @copyright (C) 2013, Tony Rogvall
%%% @doc
%%%     spi & gpio stub
%%% Created:  May 2013 by Malotte W Lönne
%%% @end
%%%-------------------------------------------------------------------
-module(io_stub).

%% Switching to lager (ale)
-define(dbg(Format, Args),
 	lager:debug("~s(~p): " ++ Format, 
		    [?MODULE, self() | Args])).

%% piface
-export([init/0,
	 init_interrupt/0,
	 read_input/0,
	 gpio_set/1,
	 gpio_clr/1]).

%% gpio
-export([init/1,
	 init/2,
	 set/1,
	 set/2,
	 clr/1,
	 clr/2,
	 set_interrupt/2,
	 set_interrupt/3,
	 set_direction/2,
	 set_direction/3]).


%% piface
init() -> 
    ?dbg("piface init.",[]),
    ok.

init_interrupt() -> 
    ?dbg("piface init interrupt.",[]),
    ok.

gpio_set(Pin) ->
    ?dbg("piface set of pin ~p.",[Pin]),
    ok.
    
gpio_clr(Pin) ->
    ?dbg("piface clr of pin ~p.",[Pin]),
    ok.

read_input() ->
    random(). %% ??

%% gpio
init(Pin) -> 
    ?dbg("gpio init of pin ~p.",[Pin]),
    ok.
init(PinReg, Pin) -> 
    ?dbg("gpio init of pin ~p:~p.",[PinReg, Pin]),
    ok.
 
set(Pin) ->
    ?dbg("gpio set of pin ~p.",[Pin]),
    ok.
set(PinReg, Pin) ->
    ?dbg("gpio set of pin ~p:~p.",[PinReg, Pin]),
    ok.
clr(Pin) ->
    ?dbg("gpio clr of pin ~p.",[Pin]),
    ok.
clr(PinReg, Pin) ->
    ?dbg("gpio clr of pin ~p:~p.",[PinReg, Pin]),
    ok.
set_interrupt(Pin, Trig) ->
    ?dbg("gpio set of interrupt trigger ~p for pin ~p.",[Trig, Pin]),
    ok.
set_interrupt(PinReg, Pin, Trig) ->
    ?dbg("gpio set of interrupt trigger ~p for pin ~p:~p.",
	 [Trig, PinReg, Pin]),
    ok.
set_direction(Pin, Dir) ->
    ?dbg("gpio set of pin direction ~p for pin ~p.",[Dir, Pin]),
    ok.
set_direction(PinReg, Pin, Dir) ->
    ?dbg("gpio set of pin direction ~p for pin ~p:~p.",
	 [Dir, PinReg, Pin]),
    ok.

random() ->
    %% Initialize
    random:seed(now()),
    %% Retreive
    random:uniform(16#ff).
