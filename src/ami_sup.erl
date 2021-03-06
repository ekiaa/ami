-module(ami_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
	supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
	{ok, {{one_for_one, 5, 10}, [
		{ami_socket_in_sup, {ami_socket_in_sup, start_link, []}, permanent, infinity, supervisor, [ami_socket_in_sup]},
		{ami_socket_out_sup, {ami_socket_out_sup, start_link, []}, permanent, infinity, supervisor, [ami_socket_out_sup]}
	]}}.

