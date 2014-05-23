-module(ami_app).

-behaviour(application).

-include("ami.hrl").

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    ami_sup:start_link().

stop(_State) ->
    ok.
