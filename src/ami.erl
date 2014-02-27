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
	send/2,
	send/3
]).

%%%-------------------------------------------------------------------
%%% API functions
%%%-------------------------------------------------------------------

create(Event, Host, Port, Username, Secret) ->
	ami_socket:start(Event, Host, Port, Username, Secret).

send(AMI, Message) ->
	ami_socket:send(AMI, Message).

send(AMI, Message, ReplyTo) ->
	ami_socket:send(AMI, Message, ReplyTo).