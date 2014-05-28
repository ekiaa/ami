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
	send/3,
	%% AMI commands
	get_var/3,
	hangup/2,
	login/4,
	mixmonitor/3,
	stop_mixmonitor/2
]).

%%%-------------------------------------------------------------------
%%% API functions
%%%-------------------------------------------------------------------

create(Event, Host, Port, Username, Secret) ->
	ami_socket_out:start(Event, Host, Port, Username, Secret).

send(AMI, Message) ->
	ami_socket_out:send(AMI, Message).

send(AMI, Message, ReplyTo) ->
	ami_socket_out:send(AMI, Message, ReplyTo).

%%%-------------------------------------------------------------------

get_var(AMI, Channel, Variable) ->
	?MODULE:send(AMI, #{<<"Action">> => <<"GetVar">>, <<"Channel">> => Channel, <<"Variable">> => Variable}).

hangup(AMI, Channel) ->
	?MODULE:send(AMI, #{<<"Action">> => <<"Hangup">>, <<"Channel">> => Channel}).

login(AMI, Username, Secret, ReplyTo) ->
	?MODULE:send(AMI, #{<<"Action">> => <<"Login">>, <<"Username">> => Username, <<"Secret">> => Secret}, ReplyTo).

mixmonitor(AMI, Channel, File) ->
	?MODULE:send(AMI, #{<<"Action">> => <<"MixMonitor">>, <<"Channel">> => Channel, <<"File">> => File}).

stop_mixmonitor(AMI, Channel) ->
	?MODULE:send(AMI, #{<<"Action">> => <<"StopMixMonitor">>, <<"Channel">> => Channel}).