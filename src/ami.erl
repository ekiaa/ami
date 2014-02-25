%%%-------------------------------------------------------------------
%%% File        : ami.erl
%%% Author      : Artem Ekimov <ekimov-artem@ya.ru>
%%% Description : 
%%% Created     : 27.01.2014
%%%-------------------------------------------------------------------

-module(ami).

-export([
	%% API functions
	connect/2,
	connect/4,
	%% AMI Actions
	login/2
]).

%%%-------------------------------------------------------------------
%%% API functions
%%%-------------------------------------------------------------------

connect(Host, Port) ->
	ami_socket:connect(Host, Port).

connect(Host, Port, Username, Secret) ->
	ami_socket:connect(Host, Port, Username, Secret).

%%%-------------------------------------------------------------------
%%% AMI Actions
%%%-------------------------------------------------------------------

login(Username, Secret) ->
	ActionID = get_action_id(),
	Msg = #{
		<<"Action">>   => <<"Login">>,
		<<"ActionID">> => ActionID,
		<<"Username">> => Username,
		<<"Secret">>   => Secret},
	ami_socket:send(Msg),
	ActionID.

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

get_action_id() ->
	{A1, A2, A3} = erlang:now(),
	erlang:list_to_binary(io_lib:format("~w~w~w", [A1, A2, A3])).