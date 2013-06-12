%%% -*- mode: nitrogen -*-
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
%%% @author Malotte W Lönne <malotte@malotte.net>
%%% @copyright (C) 2012, Tony Rogvall
%%% @doc
%%%  rfZone WebService index page.
%%%
%%%  Based on nitrogen, see documentation on http://nitrogenproject.com/
%%%
%%% @end

-module (rfzdemo_index).

-include_lib("nitrogen_core/include/wf.hrl").
-include_lib("canopen/include/co_app.hrl").
-include("rfzdemo.hrl").

%% Callbacks for nitrogen
-export([main/0, 
         title/0, 
         layout/0, 
         event/1]).

-type nitrogen_element()::term() | list(term()).
%% Nitrogen accumulator timeout ??
%% Used in comet loop functions
-define(LOOP_TIMEOUT, 9 * 1000).

main() ->
    content_type_html(),
    File = filename:join([code:lib_dir(rfzone, test),
	                  "templates","grid.html"]),
    #template { file=File }.

title() ->
    "RfZone Web Service".

layout() ->
    wf:comet(fun() -> feedback() end, feedback),
    %% Hidden dummy to keep comet alive
    wf:wire(dummy,  #hide{}),
    wf:wire(statustext, #hide{}),

    #container_12 {
        body=[
	    #grid_12 { class=header, body=header() },
	    #grid_clear {},
	    
	    #grid_12 { alpha=true, body=text() },
	    #grid_clear {},

	    #grid_4 { 
		alpha=true, %% First in row
		id=green,
		body=light(green)  },
	    #grid_4 { 
		id=yellow,
		body=light(yellow)  },
	    #grid_4 { 
		omega=true, %% Last in row
		id=red,
		body=light(red)  },

 	    #grid_clear {},
	    #grid_12 { 
		alpha=true, 
		body=[
		    #label { id=statustext, text="Result"},
		    #panel { id=status }]},

 	    #grid_clear {},
            #panel { id=dummy }, 
	    #grid_12 { body=footer() }
    ]}.

text() ->
    [
	#panel { 
	    text = "Welcome to
	            <p>
	            RfZone WebService",
	    html_encode = false,
	    style = "font-size: 24px; text-align: center"},
	#grid_clear {}
    ].

light(Colour) ->	
    [
        #flash {},
        #p{},
	#radiogroup {
	    body=[
		#panel { 
		    text = atom_to_list(Colour),
		    html_encode = false,
		    style = "font-size: 18px; color: " ++ atom_to_list(Colour)},
		#radio {
		    text="On", 
		    value="1", 
		    postback={Colour, 1}, 
		    checked=true}, 
		#br{},
		#radio {
		    text="Off", 
		    value="2", 
		    postback={Colour, 0}}]},
	#p{}
    ].


%%--------------------------------------------------------------------
%% @private
%% @doc 
%% Callback from nitrogen when an event has occured.
%% @end
%%--------------------------------------------------------------------
event({Colour, Action} = Event) ->
    ?dbg("event ~p",[Event]),
    %% Call exodm / device 1
    Result = rfzone_customer_server:digital_output("rfzone1", 
	colour2channel(Colour), 
	Action),   
   ?dbg("result ~p",[Result]),
    wf:update(flash_status, Result),
    wf:flush(),
    ok;
event(Event) ->
    ?dbg("event ~p",[Event]),
    ok.

%%--------------------------------------------------------------------
%% @doc 
%% Comet function. Initiates comet receive loop. 
%% @end
%%--------------------------------------------------------------------
-spec feedback() -> no_return().

feedback() ->
    process_flag(trap_exit, true),
    %% receice_all?
    feedback_loop().


%--------------------------------------------------------------------
%% @doc 
%% Comet receive loop.
%% Update info/table when data is available
%% @end
%%--------------------------------------------------------------------
-spec feedback_loop() -> no_return().

feedback_loop() ->
    receive
	'INIT' ->
            %% The init message is sent to the first process in a comet pool.
	    %% Nothing to do right now
	    ?dbg("feedback: got event: INIT", []),
            wf:update(dummy, "Dummy"),
	    feedback_loop();
        {'EXIT', _, Message} -> 
	    ?dbg("The user has left the page, message ~p.~n",[Message]),
	    exit(done);
	Other ->
	    %% ok or ??
	    ?dbg("feedback: got event: ~p.", [Other]),
	    feedback_loop()
    after 
        ?LOOP_TIMEOUT -> %% Nitrogen accumulator timeout ??
 	    %%?dbg("feedback: timeout, recursive call", []),
            wf:update(dummy, io_lib:format("~w",[sz_util:sec()])),
            wf:flush(),
            feedback_loop()
    end.

%%--------------------------------------------------------------------
%% @doc 
%% Common header for rfzdemo pages.
%% @end
%%--------------------------------------------------------------------
-spec header() -> nitrogen_element().

header() ->
    #panel { 
%%	class=menu, 
	body=[
%%	#image { image="/images/logo_rfzone.jpg", alt=" RfZone " },
	#br{}
    ]}.

%%--------------------------------------------------------------------
%% @doc 
%% Common footer for rfzdemo pages.
%% @end
%%--------------------------------------------------------------------
-spec footer() -> nitrogen_element().

footer() ->
    [#br{},
     #panel { 
	    class=credits,
	    body=[#br{}]}
    ].

%%--------------------------------------------------------------------
%% @doc 
%% Set nitrogen content type.
%% @end
%%--------------------------------------------------------------------
-spec content_type_html() -> nitrogen_element().

content_type_html() ->
    CharSet = 
	case gettext:lang2cset(get(gettext_language)) of
	    {ok, CSet} -> CSet;
	    _ -> "iso-8859-1"
	end,
    %% ?dbg("CharSet=~p\n", [CharSet]),
    wf:content_type("text/html; charset='"++CharSet++"'").

%%--------------------------------------------------------------------
%% @doc 
%% Convert chars to unicode binary.
%% @end
%%--------------------------------------------------------------------
-spec to_utf8(Chars::list(integer() | binary())) -> term().

to_utf8(Chars) ->
    unicode:characters_to_binary(Chars, utf32, utf8).

colour2channel(red) -> 103;
colour2channel(yellow) -> 102;
colour2channel(green) -> 101.

