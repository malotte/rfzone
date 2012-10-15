%%
%% Send fineoffset weather station data
%%
-module(fine_offset).

-compile(export_all).

-define(PREAMBLE, 16#ff).
-define(DEVID,    16#A1).  %% SENSOR?
-define(is_byte(X),  (((X) band (bnot 255)) =:= 0)).
-define(HIGH, [550,  1010]).
-define(LOW,  [1600, 1010]).

%% 
%% fine offset packet layout
%% 

%% decode data Packet pasrt in <<?DEVID, Packet:10/binary, Crc8:8>>
decode_data(<<ID:12, TempRaw:12, Humidity:8, WindAvgRaw:8,
	      WindGustRaw:8, _M:4, RainRaw:12, _:4, Direction:4 >>) ->
    Temp = (TempRaw - 400) / 10,
    WindAvgMs = round(WindAvgRaw * 34.0) / 100,
    WindGustMs = round(WindGustRaw * 34.0) / 100,
    Rain = RainRaw * 0.3,
    Dir = element(Direction+1, 
		  {n, nne, ne, ene, e, ese, se, sse,
		   s, ssw, sw, wsw, w, wnw, nw, nnw}),
    [{id,ID},
     {temprature, Temp},
     {humidity, Humidity},
     {wind_speed, WindAvgMs},
     {wind_gust, WindGustMs},
     {wind_direction, Dir},
     {rain, Rain}].

decode(<<?DEVID,Packet:10/binary,Crc>>) ->
    case crc8(Packet) of
	Crc ->
	    decode_data(Packet);
	_ ->
	    exit(crc_error)
    end.

encode_data(Opts) ->
    ID = proplists:get_value(id, Opts, 16#fff),
    Temp = proplists:get_value(temprature, Opts),
    Humidity = proplists:get_value(humidity, Opts),
    WindAvgMs = proplists:get_value(wind_speed, Opts),
    WindGustMs  = proplists:get_value(gust_speed, Opts),
    Dir = proplists:get_value(wind_direction, Opts),
    Rain = proplists:get_value(rain, Opts),

    TempRaw   = if Temp =:= undefined ->
			16#fff;
		   true ->
			trunc(10*Temp+400)
		end,
    HumidityRaw = if Humidity =:= undefined ->
			  16#00;
		     true ->
			  Humidity
		  end,
    WindAvgRaw = if WindAvgMs =:= undefined ->
			 16#00;
		    true ->
			 trunc((100*WindAvgMs)/34.0)
		 end,
    
    WindGustRaw = if WindGustMs =:= undefined ->
			  16#00;
		     true ->
			  trunc((100*WindGustMs)/34.0)
		  end,
    RainRaw     = if Rain =:= undefined ->
			  16#000;
		     true ->
			  trunc(Rain / 0.3)
		  end,
    Direction =	case Dir of
		    undefined -> 16#0;
		    n -> 0; nne -> 1; ne -> 2; ene -> 3;
		    e -> 4; ese -> 5; se -> 6; sse -> 7;
		    s -> 8; ssw -> 9; sw -> 10;wsw -> 11;
		    w -> 12;wnw -> 13;nw -> 14;nnw -> 15
		end,
    <<ID:12, TempRaw:12, HumidityRaw:8, WindAvgRaw:8,
      WindGustRaw:8, 0:4, RainRaw:12, 0:4, Direction:4 >>.

encode(Opts) ->
    Packet = encode_data(Opts),
    DevID  = proplists:get_value(devid,Opts,?DEVID),
    Crc = crc8(Packet),
    <<?PREAMBLE,DevID,Packet/binary,Crc>>.

send(Opts) ->
    Data = encode(Opts),
    Pulses = lists:append(rf_code(Data)),
    tellstick_drv:send_pulses(Pulses).
    
rf_code(Data) ->
    each_byte(
      fun(B,Acc) ->
	      [ tellstick_drv:rf_code_hl(B, 8, ?LOW, ?HIGH) | Acc]
      end, [], Data).
    
crc8(Data) ->
    crc8_update(0, Data).

crc8_update(Crc, Data) ->
    each_byte(fun crc8_byte/2, Crc, Data).

crc8_final(Crc) ->
    Crc.

crc8_byte(B, Crc) ->
    crc8_byte(8,B,Crc).

crc8_byte(0,_B,Crc) ->
    Crc;
crc8_byte(I,B,Crc) ->
    Crc1 = 
	case (Crc bxor B) band 16#80 of
	    0 -> Crc bsl 1;
	    _ -> (Crc bsl 1) bxor 16#31
	end,
    crc8_byte(I-1,B bsl 1,Crc1 band 16#ff).

%% byte iterator over iolist
each_byte(Fun, Acc, [H|T]) when ?is_byte(H) ->
    each_byte(Fun,Fun(H,Acc),T);
each_byte(Fun, Acc, [H|T]) ->
    each_byte(Fun,each_byte(Fun, Acc, H),T);
each_byte(_Fun,Acc,[]) ->
    Acc;
each_byte(Fun,Acc,<<H,T/binary>>) ->
    each_byte(Fun,Fun(H,Acc),T);
each_byte(_Fun,Acc,<<>>) ->
    Acc.



    
    
