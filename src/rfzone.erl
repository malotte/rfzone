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
%%% @copyright (C) 2010, Tony Rogvall
%%% @doc
%%%    rfZone control application.
%%%    For detailed description of the functionality see the overview.
%%%
%%% Created :  5 Jul 2010 by Tony Rogvall
%%% @end
%%%-------------------------------------------------------------------
-module(rfzone).

-behaviour(application).


%% Application API
-export([start/2, 
	 stop/1]).

%% Shortcut API
-export([start/0]).

%%%===================================================================
%%% API
%%%===================================================================
%%--------------------------------------------------------------------
%% @doc
%% Starts the application.<br/>
%% Arguments are ignored, instead the options for the application server are 
%% retreived from the application environment (sys.config).
%%
%% @end
%%--------------------------------------------------------------------
-spec start(StartType:: normal | 
			{takeover, Node::atom()} | 
			{failover, Node::atom()}, 
	    StartArgs::term()) -> 
		   {ok, Pid::pid()} |
		   {ok, Pid::pid(), State::term()} |
		   {error, Reason::term()}.

start(_StartType, _StartArgs) ->
    error_logger:info_msg("~p: start: arguments ignored.\n", [?MODULE]),
    Opts = case application:get_env(options) of
	       undefined -> [];
	       {ok, O} -> O
	   end,
    Args = [{options, Opts}],
    rfzone_sup:start_link(Args).

%%--------------------------------------------------------------------
%% @doc
%% Stops the application.
%%
%% @end
%%--------------------------------------------------------------------
-spec stop(State::term()) -> ok | {error, Error::term()}.

stop(_State) ->
    exit(stopped).

start() ->
    start_em([lager,rfzone]).

start_em([App|Apps]) ->
    %% io:format("Start: ~p\n", [App]),
    case application:start(App) of
	{error,{not_started,App1}} ->
	    start_em([App1,App|Apps]);
	{already_started,App} ->
	    start_em(Apps);
	ok ->
	    start_em(Apps);
	Error ->
	    Error
    end;
start_em([]) ->
    ok.




