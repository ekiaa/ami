%%%-------------------------------------------------------------------
%%% File        : ami_socket_in.erl
%%% Author      : Artem Ekimov <ekimov-artem@ya.ru>
%%% Description : 
%%% Created     : 27.01.2014
%%%-------------------------------------------------------------------

-module(ami_socket_in).

-behaviour(gen_server).

-include("ami.hrl").

%% API functions

-export([start/2, start_link/2]).

%% gen_server callbacks

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%====================================================================
%% API functions
%%====================================================================

start(Socket, OutSocketPid) ->
	ami_socket_in_sup:start_child([Socket, OutSocketPid]).

start_link(Socket, OutSocketPid) ->
	gen_server:start_link(?MODULE, {create, Socket, OutSocketPid}, []).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Description: Initiates the server
%%--------------------------------------------------------------------

init({create, Socket, OutSocketPid}) ->
	{ok, #{
		out      => OutSocketPid,
		% event    => Event,
		socket   => Socket,
		status   => ok,
		state    => key,
		type     => undefined,
		key      => <<>>,
		value    => <<>>,
		object   => #{},
		result   => [],
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

handle_cast(Message, State) ->
	lager:error("handle_cast: nomatch Message: ~p", [Message]),
	{stop, {error, nomatch}, State}.

%%--------------------------------------------------------------------
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------

handle_info({tcp, Socket, Data}, #{out := Pid, socket := Socket, buf := Buf} = State)->
	% lager:debug("recieve tcp data:~n~p~nState: ~p", [Data, State]),
	NewState = decode(State#{buf => <<Buf/binary, Data/binary>>}),
	% lager:debug("decode return:~n~p", [NewState]),
	case NewState of
		#{status := ok, result := List} ->
			[gen_server:cast(Pid, {decode, Message}) || Message <- List],
			{noreply, NewState};
		#{status := error} ->
			lager:error("decode error:~n~p", [NewState]),
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

decode(#{buf := <<>>, result := Result} = State) ->
	State#{status => ok, result => lists:reverse(Result)};

decode(#{status := ok} = State) ->
	decode(State#{status => undefined, result => []});

decode(#{buf := <<"\r", Buf/binary>>, state := delim} = State) ->
	decode(State#{buf => Buf, state => value});
decode(#{buf := <<"\r", Buf/binary>>} = State) ->
	decode(State#{buf => Buf});

decode(#{state := key, buf := <<"\n", Buf/binary>>, type := Type, object := Object, result := Result} = State) ->
	decode(State#{state => key, buf => Buf, type => undefined, object => #{}, result => [{Type, Object} | Result]});
decode(#{state := key, buf := <<"/", Buf/binary>>, key := <<"Asterisk Call Manager">>} = State) ->
	decode(State#{state => value, buf => Buf, type => welcome});
decode(#{state := key, buf := <<":", Buf/binary>>} = State) ->
	decode(State#{state => delim, buf => Buf});
decode(#{state := key, buf := <<C:8, Buf/binary>>, key := Key} = State) ->
	decode(State#{buf => Buf, key => <<Key/binary, C>>});

decode(#{state := delim, key := Key, buf := <<" ", Buf/binary>>} = State) ->
	case Key of
		<<"Event">>    -> decode(State#{state => value, buf => Buf, type => event});
		<<"ActionID">> -> decode(State#{state => value, buf => Buf, type => response});
		_ -> decode(State#{state => value, buf => Buf})
	end;

decode(#{state := value, buf := <<"\n", Buf/binary>>, type := welcome, key := Key, value := Value, object := Object, result := Result} = State) ->
	decode(State#{state => key, buf => Buf, type => undefined, key => <<>>, value => <<>>, object => #{}, result => [{welcome, maps:put(Key, Value, Object)} | Result]});
decode(#{state := value, buf := <<"\n", Buf/binary>>, key := Key, value := Value, object := Object} = State) ->
	decode(State#{state => key, buf => Buf, key => <<>>, value => <<>>, object => maps:put(Key, Value, Object)});
decode(#{state := value, buf := <<C:8, Buf/binary>>, value := Value} = State) ->
	decode(State#{value => <<Value/binary, C>>, buf => Buf});

decode(State) when (erlang:is_map(State)) ->
	State#{status => error}.
