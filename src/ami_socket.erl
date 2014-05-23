%%%-------------------------------------------------------------------
%%% File        : ami_socket.erl
%%% Author      : Artem Ekimov <ekimov-artem@ya.ru>
%%% Description : 
%%% Created     : 27.01.2014
%%%-------------------------------------------------------------------

-module(ami_socket).

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
	ami_socket_sup:start_child([Event, Host, Port, Username, Secret]).

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
					gen_server:call(AMI, {send, maps:put(<<"ActionID">>, ActionID, Message)});
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
			lager:debug("send message by id ~p; reply to ~p", [ActionID, Client]),
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

handle_cast({send, #{<<"ActionID">> := ActionID} = Msg, ReplyTo}, #{socket := Socket, replyto := ReplyToList} = State) ->
	Data = encode(Msg),
	case gen_tcp:send(Socket, Data) of
		ok ->
			lager:debug("send message by id ~p; send to ~p", [ActionID, ReplyTo]),
			{noreply, State#{replyto => maps:put(ActionID, {send, ReplyTo}, ReplyToList)}};
		{error, Reason} ->
			lager:error("send message error:~n~p", [Reason]),
			{stop, {error, Reason}, State}
	end;

handle_cast({connect, Host, Port, Username, Secret}, State) ->
	case gen_tcp:connect(Host, Port, [binary, {active, true}, {nodelay, true}]) of
		{ok, Socket} ->
			ami:send(self(), #{<<"Action">> => <<"Login">>, <<"Username">> => Username, <<"Secret">> => Secret}, self()),
			{noreply, State#{socket => Socket}};
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

handle_info({tcp, Socket, Data}, #{event := Event, socket := Socket, buf := Buf} = State)->
	% lager:debug("recieve tcp data:~n~p", [Data]),
	NewState = decode(State#{buf => <<Buf/binary, Data/binary>>}),
	% lager:debug("decode return:~s", [map_to_string(NewState)]),
	case NewState of
		#{status := ok, type := greeting} ->
			{noreply, NewState};
		#{status := ok, type := event, result := Message} ->
			gen_event:notify(Event, {ami_event, self(), Message}),
			{noreply, NewState};
		#{status := ok, type := response, result := #{<<"ActionID">> := ActionID} = Message, replyto := ReplyToList} ->
			case maps:find(ActionID, ReplyToList) of
				{ok, {reply, Client}} ->
					gen_server:reply(Client, {ok, Message}),
					lager:debug("reply to ~p response:~s", [Client, map_to_string(Message)]),
					{noreply, NewState#{replyto => maps:remove(ActionID, ReplyToList)}};
				{ok, {send, Client}} ->
					Client ! {ami_reply, self(), Message},
					lager:debug("send to ~p response:~s", [Client, map_to_string(Message)]),
					{noreply, NewState#{replyto => maps:remove(ActionID, ReplyToList)}};
				error ->
					{noreply, NewState}
			end;
		#{status := ok} ->
			lager:warning("nomatch decode result:~s", [map_to_string(NewState)]),
			{noreply, NewState};
		#{status := error} ->
			lager:error("decode error:~s", [map_to_string(NewState)]),
			{stop, {error, nomatch}, NewState};
		_ ->
			{noreply, NewState}
	end;

handle_info({tcp_closed, Socket}, #{socket := Socket} = State)  ->
	lager:debug("socket ~p closed", [Socket]),
	{stop, normal, State};

handle_info({ami_reply, _, _}, State) ->
	{noreply, State};

handle_info(Info, State) ->
	lager:error("handle_info: nomatch Info: ~p", [Info]),
	{stop, {error, nomatch}, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%%--------------------------------------------------------------------

terminate(_Reason, _State) ->
	ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

decode(#{buf := <<>>} = State) ->
	State;

decode(#{status := ok} = State) ->
	decode(State#{status => key, type => undefined, result => #{}});

decode(#{buf := <<"\r", Buf/binary>>} = State) ->
	decode(State#{buf => Buf});

decode(#{status := key, buf := <<"\n", Buf/binary>>} = State) ->
	State#{status => ok, buf => Buf};
decode(#{status := key, buf := <<"/", Buf/binary>>} = State) ->
	decode(State#{status => value, buf => Buf});
decode(#{status := key, buf := <<":", Buf/binary>>} = State) ->
	decode(State#{status => delim, buf => Buf});
decode(#{status := key, buf := <<C:8, Buf/binary>>, key := Key} = State) ->
	decode(State#{key => <<Key/binary, C>>, buf => Buf});

decode(#{status := delim, key := Key, buf := <<" ", Buf/binary>>} = State) ->
	case Key of
		<<"Event">>    -> decode(State#{status => value, buf => Buf, type => event});
		<<"ActionID">> -> decode(State#{status => value, buf => Buf, type => response});
		_ -> decode(State#{status => value, buf => Buf})
	end;

decode(#{status := value, buf := <<"\n", Buf/binary>>, key := <<"Asterisk Call Manager">>, value := _Value} = State) ->
	State#{status => ok, buf => Buf, key => <<>>, value => <<>>, type => greeting};
decode(#{status := value, buf := <<"\n", Buf/binary>>, key := Key, value := Value, result := Result} = State) ->
	decode(State#{status => key, buf => Buf, key => <<>>, value => <<>>, result => maps:put(Key, Value, Result)});
decode(#{status := value, buf := <<C:8, Buf/binary>>, value := Value} = State) ->
	decode(State#{value => <<Value/binary, C>>, buf => Buf});

decode(State) when (erlang:is_map(State)) ->
	State#{status => error}.

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

map_to_string(M) when erlang:is_map(M) ->
	maps:fold(
		fun
			(K, V, A) when erlang:is_binary(K), erlang:is_binary(V) -> 
				io_lib:format("~s~n~s: ~s", [A, erlang:binary_to_list(K), erlang:binary_to_list(V)]);
			(K, V, A) when erlang:is_map(V) ->
				io_lib:format("~s~n~p: ~s", [A, K, map_to_string(V)]);
			(K, V, A) ->
				io_lib:format("~s~n~p: ~p", [A, K, V])
		end, "", M);
map_to_string(V) ->
	io_lib:format("~p", [V]).

to_bin(Bin) when erlang:is_binary(Bin) -> Bin;
to_bin(Val) -> erlang:list_to_binary(io_lib:format("~p", [Val])).