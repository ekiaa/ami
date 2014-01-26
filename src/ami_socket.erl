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

-export([start/0, start_link/0, stop/0, connect/0]).

%% gen_server callbacks

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% State record

-record(state, {host, port, user, pass, socket}).

-define(State, State#state). %{}

%%====================================================================
%% API functions
%%====================================================================

start() ->
	?MODULE:start_link().

start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

stop() ->
	gen_server:call(?MODULE, stop).

connect() ->
	case {application:get_env(ami, ami_host), application:get_env(ami, ami_port)} of
		{{ok, Host}, {ok, Port}} ->
			gen_server:call(?MODULE, {connect, Host, Port});
		_ ->
			{error, <<"No host or port are specified">>}
	end.


%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Description: Initiates the server
%%--------------------------------------------------------------------

init([]) ->
	lager:debug("init"),
	{ok, #state{}};

init(Args) ->
	lager:error("init: nomatch Args: ~p", [Args]),
	{stop, {error, nomatch}}.

%%--------------------------------------------------------------------
%% Description: Handling call messages
%%--------------------------------------------------------------------

handle_call({connect, Host, Port}, _From, State) ->
	case gen_tcp:connect(Host, Port, [binary, {active, true}, {nodelay, true}]) of
		{ok, Socket} ->
			lager:debug("connect to ~p:~p success: ~p", [Host, Port, Socket]),
			{reply, ok, ?State{host = Host, port = Port, socket = Socket}};
		{error, Reason} ->
			lager:error("connect error:~n~p", [Reason]),
			{stop, {error, Reason}, {error, Reason}, State}
	end;


%% Handling stop message
handle_call(stop, _From, State) ->
	lager:debug("handle_call: stop"),
	{stop, normal, State};

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

handle_info({tcp, Socket, <<"Asterisk Call Manager/2.0.0\r\n">>}, State) when ?State.socket == Socket ->
	lager:debug("connect to Asterisk Call Manager 2.0.0 success"),
	{noreply, State};

handle_info({tcp_closed, Socket}, State) when ?State.socket == Socket ->
	lager:debug("socket ~p closed", [Socket]),
	{noreply, ?State{socket = undefined}};

handle_info(Info, State) ->
	lager:error("handle_info: nomatch Info: ~p", [Info]),
	{noreply, State}.

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
