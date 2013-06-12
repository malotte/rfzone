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
%%%  RfZone WebService support functions.
%%%
%%% @end

-module(rfzdemo).

-export([start/0,
	 stop/0,
	 rfc3339/0, 
	 rfc3339/1, 
	 gnow/0, 
	 gdate/0, 
	 gdate2datetime/1,
	 friendly_date/1, 
	 template/0, 
	 hostname/0, 
	 external_hostname/0, 
	 ip/0, 
	 port/0, 
	 servername/0, 
	 http_server/0, 
	 log_dir/0, 
	 docroot/0, 
	 top_dir/0, 
	 priv_dir/0, 
	 gettext_dir/0, 
	 i2l/1
        ]).

-import(rfzdemo_deps, [get_env/2]).

-include_lib("nitrogen_core/include/wf.hrl").
           
-define(is_bool(B), ((B =:= true) orelse (B =:= false))).

start() ->
    %% Start everything needed
    application:start(sasl),
    application:start(gettext),
    application:start(nprocreg),
    %%application:start(lager),
    lager:start(),
    application:start(ale),
    %% Customer server
    rfzone_customer_server:start([{http_port, 8102}]),
    %% Web site
    rfzdemo_inets:start_link().


stop() ->
    application:stop(ale),    
    application:stop(lager),    
    application:stop(nprocreg),
    application:stop(gettext),
    application:stop(sasl),    
    inets:stop(),
    ok.

    

log_dir()           -> get_env(log_dir, 
			       filename:join(code:lib_dir(rfzone,test),"log")).
docroot()           -> get_env(doc_root, 
			       filename:join(code:lib_dir(rfzone,test),"www")).
servername()        -> get_env(servername, "localhost").
ip()                -> get_env(ip, {127,0,0,1}).
port()              -> get_env(port, 8103).
http_server()       -> inets. 
%% get_env(http_server) - only inets available
external_hostname() -> get_env(external_hostname, hostname()).
template()          -> get_env(template, 
			       filename:join(
				 [code:lib_dir(rfzone, test), "templates",
				  "grid.html"])).
gettext_dir()       -> priv_dir().
    

hostname() ->
    {ok,Host} = inet:gethostname(),
    Host.

top_dir() ->
    filename:join(["/"|lists:reverse(tl(lists:reverse(string:tokens(filename:dirname(code:which(?MODULE)),"/"))))]).

priv_dir() ->
    top_dir()++"/priv".


%%
%% @doc Return gregorian seconds as of now()
%%
gnow() ->
    calendar:datetime_to_gregorian_seconds(calendar:local_time()).

%%
%% @doc Return gregorian seconds as of today()
%%
gdate() -> calendar:datetime_to_gregorian_seconds({date(), {0,0,0}}).

%%
%% @doc Transform Gsecs to a {date(),time()} tuple.
%%
gdate2datetime(Secs) ->
    calendar:gregorian_seconds_to_datetime(Secs).

%%
%% @doc Time as a string in a standard format.
%%
rfc3339() ->
    rfc3339(calendar:now_to_local_time(now())).

rfc3339(Gsec) when is_integer(Gsec) ->
    rfc3339(gdate2datetime(Gsec));

rfc3339({ {Year, Month, Day}, {Hour, Min, Sec}}) ->
    io_lib:format("~4..0w-~2..0w-~2..0wT~2..0w:~2..0w:~2..0w~s",
                  [Year,Month,Day, Hour, Min, Sec, zone()]).  

friendly_date(Gsec) when is_integer(Gsec) ->
    friendly_date(gdate2datetime(Gsec));

friendly_date({ {Year, Month, Day}, {Hour, Min, Sec}}) ->
    io_lib:format("~4..0w-~2..0w-~2..0w ~2..0w:~2..0w:~2..0w",
                  [Year,Month,Day, Hour, Min, Sec]).  

zone() ->
    Time = erlang:universaltime(),
    LocalTime = calendar:universal_time_to_local_time(Time),
    DiffSecs = calendar:datetime_to_gregorian_seconds(LocalTime) -
        calendar:datetime_to_gregorian_seconds(Time),
    zone(DiffSecs div 3600, (DiffSecs rem 3600) div 60).

zone(Hr, Min) when Hr < 0; Min < 0 ->
    io_lib:format("-~2..0w~2..0w", [abs(Hr), abs(Min)]);
zone(Hr, Min) when Hr >= 0, Min >= 0 ->
    io_lib:format("+~2..0w~2..0w", [Hr, Min]).


i2l(I) when is_integer(I) -> integer_to_list(I);
i2l(L) when is_list(L)    -> L.
    

