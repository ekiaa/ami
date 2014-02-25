%%%-------------------------------------------------------------------
%%% File        : ami.erl
%%% Author      : Artem Ekimov <ekimov-artem@ya.ru>
%%% Description : 
%%% Created     : 27.01.2014
%%%-------------------------------------------------------------------

-module(ami).

-export([
	connect/4,
	login/2
]).

connect(Host, Port, Username, Secret) ->
	ami_socket:connect(Host, Port, Username, Secret).

login(Username, Secret) ->
	Msg = #{
		<<"Action">>   => <<"Login">>,
		<<"ActionID">> => get_action_id(),
		<<"Username">> => to_bin(Username),
		<<"Secret">>   => to_bin(Secret)},
	ami_socket:send(Msg).

%%%-------------------------------------------------------------------

get_action_id() ->
	{A1, A2, A3} = erlang:now(),
	erlang:list_to_binary(io_lib:format("~w~w~w", [A1, A2, A3])).

to_bin(Bin) when erlang:is_binary(Bin) -> Bin;
to_bin(Val) -> erlang:list_to_binary(io_lib:format("~p", [Val])).