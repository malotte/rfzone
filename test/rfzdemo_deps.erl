%% @author Tony Rogvall tony@rogvall.se
%% @copyright YYYY Tony Rogvall.

%% @doc Various config/check functions, e.g:
%%      Ensure that the relatively-installed dependencies are on the code
%%      loading path, and locate resources relative
%%      to this application's path.

-module(rfzdemo_deps).

-export([get_env/2]).

%% @spec get_env() -> String
%% @doc Get an application environment variable; fallback to a default value.
get_env(Key, Default) ->
    case application:get_env(rfzdemo, Key) of
        {ok, Value} -> Value;
        _           -> Default
    end.

