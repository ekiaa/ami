%%%-------------------------------------------------------------------
%%% File        : ami.erl
%%% Author      : Artem Ekimov <ekimov-artem@ya.ru>
%%% Description : 
%%% Created     : 27.01.2014
%%%-------------------------------------------------------------------

-module(ami).

-export([
	%% API functions
	create/5,
	%% AMI Actions
	login/3
]).

%%%-------------------------------------------------------------------
%%% API functions
%%%-------------------------------------------------------------------

create(Event, Host, Port, Username, Secret) ->
	ami_socket:start(Event, Host, Port, Username, Secret).

%%%-------------------------------------------------------------------
%%% AMI Actions
%%%-------------------------------------------------------------------

login(AMI, Username, Secret) ->
	ActionID = get_action_id(),
	Msg = #{
		<<"Action">>   => <<"Login">>,
		<<"ActionID">> => ActionID,
		<<"Username">> => Username,
		<<"Secret">>   => Secret},
	ami_socket:send(AMI, Msg),
	ActionID.

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

get_action_id() ->
	{A1, A2, A3} = erlang:now(),
	erlang:list_to_binary(io_lib:format("~w~w~w", [A1, A2, A3])).