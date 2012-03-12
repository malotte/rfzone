%%%-------------------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2010, Tony Rogvall
%%% @doc
%%%    Tellstick application supervisor.
%%% @end
%%% Created :  6 November 2011
%%%-------------------------------------------------------------------

-module(tellstick_sup).

-behaviour(supervisor).

%% API
-export([start_link/1, stop/1]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor. <br/>
%% Arguments are sent on to the supervisor.
%%
%% @end
%%--------------------------------------------------------------------
-spec start_link(Args::list(term())) -> 
			{ok, Pid::pid()} | 
			ignore | 
			{error, Error::term()}.

start_link(Args) ->
    case supervisor:start_link({local, ?MODULE}, ?MODULE, Args) of
	{ok, Pid} ->
	    %% io:format("~p: start_link: started process ~p\n", [?MODULE, Pid]),
	    {ok, Pid, {normal, Args}};
	Error -> 
	    io:format("~p: start_link: Failed to start process, reason ~p\n", 
		      [?MODULE, Error]),
	    Error
    end.

%%--------------------------------------------------------------------
%% @doc
%% Stops the supervisor.
%%
%% @end
%%--------------------------------------------------------------------
-spec stop(StartArgs::list(term())) -> ok | {error, Error::term()}.

stop(_StartArgs) ->
    exit(stopped).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================
%% @private
init(TArgs) ->
    %% io:format("~p: Starting up\n", [?MODULE]),
    %% io:format("~p: init: Opts = ~p\n", [?MODULE, TArgs]),
    I = tellstick_srv,
    Opts = proplists:get_value(options, TArgs, []),	    
    Tellstick = {I, {I, start_link, [Opts]}, permanent, 5000, worker, [I]},
    io:format("~p: About to start ~p\n", [?MODULE,Tellstick]),
    {ok, { {one_for_one, 0, 300}, [Tellstick]} }.

