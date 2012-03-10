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

-behaviour(application).


%% API
-export([start/2, stop/1]).

%%%===================================================================
%%% API
%%%===================================================================
%%--------------------------------------------------------------------
%% @private
%% @spec start(StartType, StartArgs) -> {ok, Pid} |
%%                                      {ok, Pid, State} |
%%                                      {error, Reason}
%%      StartType = normal | {takeover, Node} | {failover, Node}
%%      StartArgs = term()
%% @doc
%% This function is called whenever an application is started using
%% application:start/[1,2], and should start the processes of the
%% application. If the application is structured according to the OTP
%% design principles as a supervision tree, this means starting the
%% top supervisor of the tree.
%%
%% @end
%%--------------------------------------------------------------------
start(_StartType, _StartArgs) ->
    io:format("~p: Starting up\n", [?MODULE]),
    Opts = case application:get_env(options) of
	       undefined -> [];
	       {ok, O} -> O
	   end,
    Args = [{options, Opts}],
    io:format("~p: Args=~p\n", [?MODULE,Args]),
    tellstick_sup:start_link(Args).

stop(_State) ->
    ok.
