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
%%%    Defines needed for rfzone test.
%%%
%%% Created : May 2013 by Malotte W Lönne
%%% @end
%%%-------------------------------------------------------------------
-ifndef(RFZONE_TEST_HRL).
-define(RFZONE_TEST_HRL, true).

-define(RF_ACCOUNT, "rfzone").
-define(RF_ADMIN, "rfzone-admin").
-define(RF_PASS, "rfzonepassw").
-define(RF_YANG, "rfzone.yang").
-define(RF_SET, "rfzset").
-define(RF_TYPE, "rfztype").
-define(RF_PROT, "exodm_bert").
-define(RF_GROUP, "rfzgroup").
-define(RF_DEVICE1, "rfzone1").
-define(RF_DEVICE2, "rfzone2").
-define(RF_DEVICE_NR1, "+46768428999").
-define(RF_DEVICE_NR2, "+46706652043").
-define(RF_SERV_KEY, "1").
-define(RF_DEV_KEY, "99").

-define(v(Pat, Expr), {Pat,Pat} = {Pat, Expr}).

-endif.
