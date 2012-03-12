%%%-------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2010, Tony Rogvall
%%% @doc
%%%    Tellstick control application.
%%%    For detailed description of the functionality see the overview.
%%%
%%% Created :  5 Jul 2010 by Tony Rogvall
%%% @end
%%%-------------------------------------------------------------------
-module(tellstick).

-behaviour(application).


%% API
-export([start/2, stop/1]).

%%%===================================================================
%%% API
%%%===================================================================
%%--------------------------------------------------------------------
%% @doc
%% Starts the application.<br/>
%% Arguments are ignored, instead the options for the application server is 
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
    %% io:format("~p: Starting up\n", [?MODULE]),
    Opts = case application:get_env(options) of
	       undefined -> [];
	       {ok, O} -> O
	   end,
    Args = [{options, Opts}],
    %% io:format("~p: Args=~p\n", [?MODULE,Args]),
    tellstick_sup:start_link(Args).

%%--------------------------------------------------------------------
%% @doc
%% Stops the application.
%%
%% @end
%%--------------------------------------------------------------------
-spec stop(State::term()) -> ok | {error, Error::term()}.

stop(_State) ->
    exit(stopped).
