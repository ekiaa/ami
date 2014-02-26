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

-export([start/5, start_link/5, send/2]).

%% gen_server callbacks

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%====================================================================
%% API functions
%%====================================================================

start(Event, Host, Port, Username, Secret) ->
	ami_socket_sup:start_child([Event, Host, Port, Username, Secret]).

start_link(Event, Host, Port, Username, Secret) ->
	gen_server:start_link(?MODULE, {create, Event, Host, Port, Username, Secret}, []).

send(AMI, Msg) ->
	gen_server:cast(AMI, {send, self(), Msg}).


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
		key      => <<>>,
		value    => <<>>,
		list     => [],
		result   => undefined,
		buf      => <<>>}};

init(Args) ->
	lager:error("init: nomatch Args: ~p", [Args]),
	{stop, {error, nomatch}}.

%%--------------------------------------------------------------------
%% Description: Handling call messages
%%--------------------------------------------------------------------

handle_call(Request, From, State) ->
	lager:error("handle_call: nomatch Request: ~p; From ~p ", [Request, From]),
	{stop, {error, nomatch}, {error, nomatch}, State}.

%%--------------------------------------------------------------------
%% Description: Handling cast messages
%%--------------------------------------------------------------------

handle_cast({connect, Host, Port, Username, Secret}, State) ->
	case gen_tcp:connect(Host, Port, [binary, {active, true}, {nodelay, true}]) of
		{ok, Socket} ->
			lager:debug("connect to ~p:~p success: ~p", [Host, Port, Socket]),
			ami:login(self(), Username, Secret),
			{noreply, State#{socket => Socket}};
		{error, Reason} ->
			lager:error("connect error:~n~p", [Reason]),
			{stop, {error, Reason}, State}
	end;

handle_cast({send, ReplyTo, #{<<"ActionID">> := ActionID} = Msg}, #{socket := Socket} = State) ->
	Data = encode(Msg),
	% lager:debug("send data:~n~p", [Data]),
	case gen_tcp:send(Socket, Data) of
		ok ->
			lager:debug("send message by id ~p; reply to ~p", [ActionID, ReplyTo]),
			{noreply, State};
		{error, Reason} ->
			lager:error("send message error:~n~p", [Reason]),
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
	case NewState of
		#{status := ok, result := undefined} ->
			{noreply, NewState};
		#{status := ok, result := Msg} ->
			gen_event:notify(Event, {ami_event, self(), Msg}),
			{noreply, NewState};
		#{status := error} ->
			{stop, {error, nomatch}, NewState};
		_ ->
			% lager:debug("nomatch decode result:~s", [map_to_string(NewState)]),
			{noreply, NewState}
	end;

handle_info({tcp_closed, Socket}, #{socket := Socket} = State)  ->
	lager:debug("socket ~p closed", [Socket]),
	{stop, normal, State};

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
	decode(State#{status => key});

decode(#{buf := <<"\r", Buf/binary>>} = State) ->
	decode(State#{buf => Buf});

decode(#{status := key, buf := <<"\n", Buf/binary>>, list := List} = State) ->
	State#{status => ok, buf => Buf, result => maps:from_list(lists:reverse(List)), list => []};
decode(#{status := key, buf := <<"/", Buf/binary>>} = State) ->
	decode(State#{status => value, buf => Buf});
decode(#{status := key, buf := <<":", Buf/binary>>} = State) ->
	decode(State#{status => delim, buf => Buf});
decode(#{status := key, buf := <<C:8, Buf/binary>>, key := Key} = State) ->
	decode(State#{key => <<Key/binary, C>>, buf => Buf});

decode(#{status := delim, buf := <<" ", Buf/binary>>} = State) ->
	decode(State#{status => value, buf => Buf});

decode(#{status := value, buf := <<"\n", Buf/binary>>, key := <<"Asterisk Call Manager">>, value := _Value, list := []} = State) ->
	State#{status => ok, buf => Buf, key => <<>>, value => <<>>, result => undefined};
decode(#{status := value, buf := <<"\n", Buf/binary>>, key := Key, value := Value, list := List} = State) ->
	decode(State#{status => key, buf => Buf, key => <<>>, value => <<>>, list => [{Key, Value} | List]});
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

map_to_string(M) when erlang:is_map(M) ->
	maps:fold(
		fun
			(K, V, A) when erlang:is_binary(K), erlang:is_binary(V) -> 
				io_lib:format("~s~n~s: ~s", [A, erlang:binary_to_list(K), erlang:binary_to_list(V)]); 
			(K, V, A) ->
				io_lib:format("~s~n~p: ~p", [A, K, V])
		end, "", M);
map_to_string(V) ->
	io_lib:format("~p", [V]).

to_bin(Bin) when erlang:is_binary(Bin) -> Bin;
to_bin(Val) -> erlang:list_to_binary(io_lib:format("~p", [Val])).