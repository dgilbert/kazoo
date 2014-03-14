%%%-------------------------------------------------------------------
%%% @author Duane Gilbert
%%% @copyright (C) 2014, <PATLive>
%%% @doc
%%%
%%% @end
%%% Created : 11. Mar 2014 5:09 PM
%%%-------------------------------------------------------------------
-module(caller10_contests).
-author("Duane Gilbert").

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

%% ETS Related
-export([table_id/0
  , table_options/0
  , find_me_function/0
  , gift_data/0
  , load_contests/0
  , created/1
  , updated/1
  , deleted/1
]).

-include("caller10.hrl").

-define(SERVER, ?MODULE).
-define(LOAD_WINDOW, whapps_config:get_integer(<<"caller10">>, <<"load_window_size_s">>, 3600)).


-record(state, {is_writeable='false' :: boolean()}).
-type state() :: #state{}.

-record(contest, {id :: ne_binary()
  ,prior_time :: pos_integer()
  ,start_time :: pos_integer()
  ,end_time :: pos_integer()
  ,after_time :: pos_integer()
  ,doc :: api_object()
  ,handling_app :: api_binary()
  ,numbers :: ne_binaries()
  ,account_id :: ne_binary()
}).
-type contest() :: #contest{}.
-type contests() :: [#contest{},...] | [].

-export_type([contest/0
              , contests/0
            ]).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([]) ->
  {ok, #state{}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
  {reply, Reply :: term(), NewState :: #state{}} |
  {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_cast({'load_contest', #contest{id=Id}=Contest}
    ,#state{is_writeable='true'}=State
) ->
  case ets:insert_new(table_id(), Contest) of
    'false' -> lager:debug("contest ~s already loaded", [Id]);
    'true' -> lager:debug("loaded contest ~s", [Id])
  end,
  {'noreply', State};
handle_cast({'update_contest', #contest{id=Id}=Contest}
    ,#state{is_writeable='true'}=State
) ->
  'true' = ets:insert(table_id(), Contest),
  lager:debug("updated contest ~s", [Id]),
  {'noreply', State}e;
handle_cast({'delete_contest', Id}
    ,#state{is_writeable='true'}=State
) ->
  'true' = ets:delete(table_id(), Id),
  lager:debug("deleted contest ~s", [Id]),
  {'noreply', State};
handle_cast(_Request, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->  {noreply, NewState :: #state{}} |
                                                                     {noreply, NewState :: #state{}, timeout() | hibernate} |
                                                                     {stop, Reason :: term(), NewState :: #state{}}).

handle_info({'ETS-TRANSFER', _TableId, _From, _GiftData}, State) ->
  lager:debug("recv ETS table ~p from ~p", [_TableId, _From]),
  _Pid = spawn(?MODULE, 'load_contests', []),
  lager:debug("loading contests in ~p", [_Pid]),
  {'noreply', State#state{is_writeable='true'}};
handle_info(_Info, State) ->
  {'noreply', State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
  {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
-spec load_contests() -> 'ok'.
load_contests() ->
  wh_util:put_callid(?MODULE),
  case couch_mgr:get_results(<<"contests">>, <<"contests/accounts_listing">>, [{'reduce', 'false'}]) of
    {'ok', []} ->
      lager:debug("no accounts found in the aggregate");
    {'ok', Accounts} ->
      load_contests(Accounts),
      lager:debug("loaded ~p contest accounts", [length(Accounts)]);
    {'error', 'not_found'} ->
      lager:debug("aggregate DB not found or view is missing"),
      caller10_maintenance:refresh_contests_db(),
      load_contests();
    {'error', _E} ->
      lager:debug("unable to load contest accounts: ~p", [_E])
  end.

-spec load_contests(wh_json:objects()) -> 'ok'.
load_contests(Accounts) ->
  [load_account_contests(wh_json:get_value(<<"key">>, Account)) || Account <- Accounts],
  'ok'.

-spec refresh_contests_db() -> 'ok'.
refresh_contests_db() ->
  case couch_mgr:db_exists(<<"contests">>) of
    'true' -> refresh_view();
    'false' ->
      init_db(),
      refresh_view()
  end,
  'ok'.

-spec init_db() -> boolean().
init_db() ->
  io:format("creating 'contests' aggregate database~n", []),
  couch_mgr:db_create(<<"contests">>).

-spec refresh_view() -> {'ok', wh_json:object()} |
{'error', _}.
refresh_view() ->
  io:format("refreshing contests design doc~n", []),
  couch_mgr:revise_doc_from_file(<<"contests">>, 'crossbar', <<"views/contests.json">>).

-spec load_account_contests(ne_binary()) -> 'ok'.
load_account_contests(AccountId) ->
  AccountDb = wh_util:format_account_id(AccountId, 'encoded'),
  Now = wh_util:current_tstamp(),
  Options = ['include_docs'
    ,{'startkey', Now}
    ,{'endkey', Now + ?LOAD_WINDOW}
  ],
  case couch_mgr:get_results(AccountDb, <<"contests/listing_by_begin_time">>, Options) of
    {'ok', []} ->
      lager:debug("account ~s is in aggregate, but has no contests coming in the future (after ~b)", [AccountId, Now]),
      couch_mgr:del_doc(<<"contests">>, AccountId),
      'ok';
    {'ok', Contests} ->
      [load_account_contest(wh_json:get_value(<<"doc">>, Contest))
        || Contest <- Contests
      ];
    {'error', _E} ->
      lager:debug("failed to load contests from account ~s: ~p", [AccountId, _E])
  end.

-spec load_account_contest(wh_json:object()) -> 'ok'.
load_account_contest(ContestJObj) ->
  gen_server:cast(?MODULE, {'load_contest', jobj_to_record(ContestJObj)}).

-spec jobj_to_record(wh_json:object()) -> contest().
jobj_to_record(JObj) ->
  #contest{id = wh_json:get_value(<<"_id">>, JObj)
  ,prior_time = wh_json:get_integer_value(<<"prior_time">>, JObj)
  ,start_time = wh_json:get_integer_value(<<"start_time">>, JObj)
  ,end_time = wh_json:get_integer_value(<<"end_time">>, JObj)
  ,after_time = wh_json:get_integer_value(<<"after_time">>, JObj)
  ,doc = JObj
  ,handling_app = 'undefined'
  ,numbers = []
  ,account_id = wh_json:get_value(<<"pvt_account_id">>, JObj)
  }.
%%%===================================================================
%%% ETS Related
%%%===================================================================
-spec table_id() -> ?MODULE.
table_id() ->
  ?MODULE.
-spec table_options() -> list().
table_options() ->
  ['set'
   , 'protected'
   , {'keypos'
   , #contest.id }
   , 'named_table'
  ].

-spec find_me_function() -> api_pid().
find_me_function() ->
  whereis(?MODULE).
-spec gift_data() -> ok.
gift_data() ->
  ok.




-spec created(wh_json:object()) -> 'ok'.
created(JObj) ->
  gen_server:cast(?MODULE, {'load_contest', jobj_to_record(JObj)}).

-spec updated(wh_json:object()) -> 'ok'.
updated(JObj) ->
  gen_server:cast(?MODULE, {'update_contest', jobj_to_record(JObj)}).

-spec deleted(ne_binary()) -> 'ok'.
deleted(DocId) ->
  gen_server:cast(?MODULE, {'delete_contest', DocId}).

