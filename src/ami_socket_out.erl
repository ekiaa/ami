%%%-------------------------------------------------------------------
%%% File        : ami_socket_out.erl
%%% Author      : Artem Ekimov <ekimov-artem@ya.ru>
%%% Description : 
%%% Created     : 27.01.2014
%%%-------------------------------------------------------------------

-module(ami_socket_out).

-behaviour(gen_server).

-include("ami.hrl").

%% API functions

-export([start/5, start_link/5, send/2, send/3]).

%% gen_server callbacks

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%====================================================================
%% API functions
%%====================================================================

start(Event, Host, Port, Username, Secret) ->
	ami_socket_out_sup:start_child([Event, Host, Port, Username, Secret]).

start_link(Event, Host, Port, Username, Secret) ->
	gen_server:start_link(?MODULE, {create, Event, Host, Port, Username, Secret}, []).

send(AMI, Message) ->
	send(AMI, Message, undefined).

send(AMI, Message, ReplyTo) ->
	case verify_ami_message(Message) of
		true ->
			ActionID = get_action_id(),
			case ReplyTo of
				undefined ->
					gen_server:call(AMI, {send, maps:put(<<"ActionID">>, ActionID, Message)}, infinity);
				_ ->
					gen_server:cast(AMI, {send, maps:put(<<"ActionID">>, ActionID, Message), ReplyTo}),
					{ok, ActionID}
			end;
		false ->
			{error, not_verified}
	end.


%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Description: Initiates the server
%%--------------------------------------------------------------------

init({create, Event, Host, Port, Username, Secret}) ->
	gen_server:cast(self(), {connect, Host, Port, Username, Secret}),
	{ok, #{
		in       => undefined,
		event    => Event,
		socket   => undefined,
		status   => ok,
		type     => undefined,
		key      => <<>>,
		value    => <<>>,
		list     => [],
		result   => #{},
		buf      => <<>>,
		replyto  => #{}}};

init(Args) ->
	lager:error("init: nomatch Args: ~p", [Args]),
	{stop, {error, nomatch}}.

%%--------------------------------------------------------------------
%% Description: Handling call messages
%%--------------------------------------------------------------------

handle_call({send, #{<<"ActionID">> := ActionID} = Msg}, Client, #{socket := Socket, replyto := ReplyToList} = State) ->
	Data = encode(Msg),
	case gen_tcp:send(Socket, Data) of
		ok ->
			% lager:debug("send message by id ~p; reply to ~p", [ActionID, Client]),
			{noreply, State#{replyto => maps:put(ActionID, {reply, Client}, ReplyToList)}};
		{error, Reason} ->
			lager:error("send message error:~n~p", [Reason]),
			{stop, {error, Reason}, State}
	end;

handle_call(Request, From, State) ->
	lager:error("handle_call: nomatch Request: ~p; From ~p ", [Request, From]),
	{stop, {error, nomatch}, {error, nomatch}, State}.

%%--------------------------------------------------------------------
%% Description: Handling cast messages
%%--------------------------------------------------------------------

handle_cast({decode, Message}, #{event := EventMgr, replyto := ReplyToList} = State) ->
	case Message of
		{event, Event} ->
			gen_event:notify(EventMgr, {ami_event, self(), Event}),
			{noreply, State};
		{response, #{<<"ActionID">> := ActionID} = Response} ->
			case maps:find(ActionID, ReplyToList) of
				{ok, {reply, Client}} ->
					gen_server:reply(Client, {ok, Response}),
					{noreply, State#{replyto => maps:remove(ActionID, ReplyToList)}};
				{ok, {send, Client}} ->
					Client ! {ami_reply, self(), Response},
					{noreply, State#{replyto => maps:remove(ActionID, ReplyToList)}};
				error ->
					{noreply, State}
			end;
		{welcome, #{<<"Asterisk Call Manager">> := Version}} ->
			lager:debug("Asterisk Call Manager version: ~s", [Version]),
			{noreply, State};
		_ ->
			lager:error("Nomatch message: ~p", [Message]),
			{noreply, State}
	end;

handle_cast({send, #{<<"ActionID">> := ActionID} = Msg, ReplyTo}, #{socket := Socket, replyto := ReplyToList} = State) ->
	Data = encode(Msg),
	case gen_tcp:send(Socket, Data) of
		ok ->
			% lager:debug("send message by id ~p; send to ~p", [ActionID, ReplyTo]),
			{noreply, State#{replyto => maps:put(ActionID, {send, ReplyTo}, ReplyToList)}};
		{error, Reason} ->
			lager:error("send message error:~n~p", [Reason]),
			{stop, {error, Reason}, State}
	end;

handle_cast({connect, Host, Port, Username, Secret}, State) ->
	case gen_tcp:connect(Host, Port, [binary, {active, true}, {nodelay, true}]) of
		{ok, Socket} ->
			{ok, InPid} = ami_socket_in:start(Socket, self()),
			ok = gen_tcp:controlling_process(Socket, InPid),
			erlang:link(InPid),
			ami:login(self(), Username, Secret, self()),
			{noreply, State#{in => InPid, socket => Socket}};
		{error, Reason} ->
			lager:error("gen_tcp:connect() error:~n~p", [Reason]),
			{stop, {error, Reason}, State}
	end;

handle_cast(Message, State) ->
	lager:error("handle_cast: nomatch Message: ~p", [Message]),
	{stop, {error, nomatch}, State}.

%%--------------------------------------------------------------------
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------

handle_info({ami_reply, _, _}, State) ->
	{noreply, State};

handle_info(Info, State) ->
	lager:error("handle_info: nomatch Info: ~p", [Info]),
	{stop, {error, nomatch}, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%%--------------------------------------------------------------------

terminate(normal, _) -> ok;

terminate(Reason, State) -> lager:error("terminate reason:~n~p~nState: ~p", [Reason, State]).

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

encode(Msg) ->
	Data = maps:fold(
		fun
			(K, V, A) when erlang:is_binary(K), erlang:is_binary(V) -> 
				<<A/binary, K/binary, ": ", V/binary, "\r\n">>;
			(K, V, A) when erlang:is_binary(K) ->
				<<A/binary, K/binary, ": ", (to_bin(V))/binary, "\r\n">>;
			(K, V, A) when erlang:is_binary(V) ->
				<<A/binary, (to_bin(K))/binary, ": ", V/binary, "\r\n">>;
			(K, V, A) ->
				<<A/binary, (to_bin(K))/binary, ": ", (to_bin(V))/binary, "\r\n">>
		end, <<>>, Msg),
	<<Data/binary, "\r\n">>.

%%--------------------------------------------------------------------

verify_ami_message(Message) ->
	maps:fold(
		fun
			(K, V, true) when erlang:is_binary(K), erlang:is_binary(V) -> true;
			(_, _, _) -> false
		end, true, Message).

get_action_id() ->
	{A1, A2, A3} = erlang:now(),
	erlang:list_to_binary(io_lib:format("~w~w~w", [A1, A2, A3])).

% map_to_string(M) when erlang:is_map(M) ->
% 	maps:fold(
% 		fun
% 			(K, V, A) when erlang:is_binary(K), erlang:is_binary(V) -> 
% 				io_lib:format("~s~n~s: ~s", [A, erlang:binary_to_list(K), erlang:binary_to_list(V)]);
% 			(K, V, A) when erlang:is_map(V) ->
% 				io_lib:format("~s~n~p: ~s", [A, K, map_to_string(V)]);
% 			(K, V, A) ->
% 				io_lib:format("~s~n~p: ~p", [A, K, V])
% 		end, "", M);
% map_to_string(V) ->
% 	io_lib:format("~p", [V]).

to_bin(Bin) when erlang:is_binary(Bin) -> Bin;
to_bin(Val) -> erlang:list_to_binary(io_lib:format("~p", [Val])).