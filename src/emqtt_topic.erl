

-module(emqtt_topic).

-include("emqtt.hrl").

-export([start_link/0,
		match/1,
		insert/1,
		delete/1]).

-behaviour(gen_server).

-export([init/1,
		handle_call/3,
		handle_cast/2,
		handle_info/2,
		terminate/2,
		code_change/3]).

-record(state, {}).

start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

match(Topic) when is_binary(Topic) ->
	DirectMatches = mnesia:dirty_read(direct_topic, Topic),
	Words = topic_split(Topic), 
	WildcardMatches =  lists:append([
		mnesia:dirty_read(wildcard_topic, Key)	|| 
			Key <- mnesia:dirty_all_keys(wildcard_topic), topic_match(Words, Key)
	]),
	DirectMatches ++ WildcardMatches.


insert(Topic) when is_binary(Topic) ->
	gen_server:call(?MODULE, {insert, Topic}).

delete(Topic) when is_binary(Topic) ->
	gen_server:cast(?MODULE, {delete, Topic}).

init([]) ->
	{atomic, ok} = mnesia:create_table(
					direct_topic, [
					{ram_copies, [node()]}, 
					{attributes, record_info(fields, direct_topic)}]),
	{atomic, ok} = mnesia:create_table(
					wildcard_topic, [
					{ram_copies, [node()]}, 
					{attributes, record_info(fields, wildcard_topic)}]),
	{ok, #state{}}.

handle_call({insert, Topic}, _From, State) ->
	Words = topic_split(Topic),
	Reply =
	case topic_type(Words) of
	direct -> 
		mnesia:dirty_write(#direct_topic{name=Topic});
	wildcard -> 
		mnesia:dirty_write(#wildcard_topic{words=Words})
	end,
	{reply, Reply, State};

handle_call(Req, _From, State) ->
	{stop, {badreq, Req}, State}.

handle_cast({delete, Topic}, State) ->
	Words = topic_split(Topic),
	case topic_type(Words) of
	direct ->
		mnesia:dirty_delete(direct_topic, Topic);
	wildcard -> 
		mnesia:direct_delete(wildcard_topic, Words)
	end,
	{noreply, State};

handle_cast(Msg, State) ->
	{stop, {badmsg, Msg}, State}.  

handle_info(Info, State) ->
	{stop, {badinfo, Info}, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, _State, _Extra) ->
	ok.

topic_type([]) ->
	direct;
topic_type([<<"#">>]) ->
	wildcard;
topic_type([<<"+">>|_T]) ->
	wildcard;
topic_type([_|T]) ->
	topic_type(T).

topic_match([], []) ->
	true;

topic_match([H|T1], [H|T2]) ->
	topic_match(T1, T2);

topic_match([_H|T1], [<<"+">>|T2]) ->
	topic_match(T1, T2);

topic_match(_, [<<"#">>]) ->
	true;

topic_match([], [_H|_T2]) ->
	false.
	
topic_split(S) ->
	binary:split(S, [<<"/">>], [global]).
	
