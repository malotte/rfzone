%%%---- BEGIN COPYRIGHT -------------------------------------------------------
%%%
%%% Copyright (C) 2007 - 2013, Rogvall Invest AB, <tony@rogvall.se>
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
%%%---- END COPYRIGHT ---------------------------------------------------------
%%% @author Malotte W Lönne <malotte@malotte.net>
%%% @copyright (C) 2013, Tony Rogvall
%%% @doc
%%%    Defines needed for seazone.
%%% @end
%%% Created : 27:th September 2012 by Malotte W Lönne
%%%-------------------------------------------------------------------
-ifndef(RFZONE_HRL).
-define(RFZONE_HRL, true).

%% Switching to lager (ale)
-define(dbg(Format, Args),
 	lager:debug("~s(~p): " ++ Format, 
		    [?MODULE, self() | Args])).

%% Convenience defines (also in canopen.hrl)
-ifndef(ee).
-define(ee(String, List), error_logger:error_msg(String, List)).
-endif.
-ifndef(ei).
-define(ei(String, List),  error_logger:info_msg(String, List)).
-endif.

-endif.
