-module(mod_hacker_news).

%% Behaviors
-behaviour(gen_mod).

%% Includes
-include("mongoose.hrl").
-include("ejabberd_commands.hrl").
-include("jlib.hrl").
-include("mongoose_config_spec.hrl").

%% Macros
-define(CACHE_TOPSTORIES, cache_topstories).
-define(METRIC_TOPSTORIES, get_topstories_response).

%% gen_mod callbacks
-export([start/2,
         stop/1,
         config_spec/0]).

%% gen_iq_handler handlers
-export([process_iq/4, user_send/4]).

%% Cache
-export([cache_topstories/1]).

%% API
-export([get_topstories/0]).

%% Types
-type error() :: error | {error, any()}.

%%
%% gen_mod callbacks
%%

-spec start(jid:server(), list()) -> ok.
start(Domain, Opts) ->
    _ = mongoose_metrics:ensure_metric(Domain, [?MODULE, ?METRIC_TOPSTORIES], spiral),
    OptsMap = #{
        url => gen_mod:get_opt(topstories_url, Opts, "https://hacker-news.firebaseio.com/v0/topstories.json?print=pretty"),
        total => gen_mod:get_opt(topstories_total, Opts, 50),
        interval => gen_mod:get_opt(topstories_interval, Opts, 300000),
        retry => gen_mod:get_opt(topstories_retry, Opts, 10),
        domain => Domain
    },
    ok = cache_topstories(OptsMap),
    mod_disco:register_feature(Domain, ?NS_HACKER_NEWS),
    [ ejabberd_hooks:add(Hook, Domain, ?MODULE, Handler, Priority)
      || {Hook, Handler, Priority} <- hook_handlers() ],
    gen_iq_handler:add_iq_handler(ejabberd_sm, Domain, ?NS_HACKER_NEWS,
                                  ?MODULE, process_iq, no_queue),
    ok.

-spec stop(jid:server()) -> ok.
stop(Domain) ->
    gen_iq_handler:remove_iq_handler(ejabberd_sm, Domain, ?NS_HACKER_NEWS),
    [ ejabberd_hooks:delete(Hook, Domain, ?MODULE, Handler, Priority)
      || {Hook, Handler, Priority} <- hook_handlers() ],
    ok.

-spec config_spec() -> mongoose_config_spec:config_section().
config_spec() ->
    #section{
       items = #{<<"topstories_url">> => #option{type = string, validate = non_empty},
                 <<"topstories_total">> => #option{type = integer, validate = positive},
                 <<"topstories_interval">> => #option{type = integer, validate = positive},
                 <<"topstories_retry">> => #option{type = integer, validate = positive}
                }
      }.

-spec hook_handlers() -> list().
hook_handlers() ->
    [{user_send_packet, user_send, 100}].

%%
%% user_send_packet handler
%%

user_send(Acc, _JID, _From, _Packet) ->
    ejabberd_c2s:run_remote_hook(self(), ?MODULE, init),
    Acc.

%%
%% gen_iq_handler handlers
%%

-spec process_iq(jid:jid(), mongoose_acc:t(), jid:jid(), jlib:iq()) -> {mongoose_acc:t(), jlib:iq()} | error().
process_iq(From, _To, Acc, #iq{xmlns = ?NS_HACKER_NEWS, type = get} = IQ) ->
    IQResp = case lists:member(From#jid.lserver, ?MYHOSTS) of
        true ->
            process_local_iq(IQ);
        false ->
            iq_error(IQ, [mongoose_xmpp_errors:item_not_found()])
    end,
    {Acc, IQResp};
process_iq(_From, _To, Acc, #iq{} = IQ) ->
    {Acc, iq_error(IQ, [mongoose_xmpp_errors:bad_request()])}.

process_local_iq(IQ) ->
    try
        create_topstories_response(IQ)
    catch
        _:_ ->
            iq_error(IQ, [mongoose_xmpp_errors:internal_server_error()])
    end.

iq_error(IQ, SubElements) when is_list(SubElements) ->
    IQ#iq{type = error, sub_el = SubElements}.

create_topstories_response(IQ) ->
    Topstories = get_topstories(),
    IQ#iq{type = result,
          sub_el = [#xmlel{name = <<"items">>,
                           attrs = [{<<"xmlns">>, ?NS_HACKER_NEWS}],
                           children = [topstories_to_xmlel(jiffy:encode(Topstories))]}]}.

topstories_to_xmlel(Data) ->
    #xmlel{name = <<"topstories">>,
           children = [#xmlcdata{content = Data}]}.

%%
%% API
%%

-spec get_topstories() -> Res :: list().
get_topstories() ->
    persistent_term:get(?CACHE_TOPSTORIES, []).

-spec cache_topstories(Data :: maps:map()) -> ok.
cache_topstories(#{url := Url, total := Total,
                   interval := Interval,
                   retry := Retry, domain := Domain} = Opts) ->
    _ = mongoose_metrics:update(Domain, [?MODULE, ?METRIC_TOPSTORIES], 1),
    _ = timer:apply_after(Interval, ?MODULE, ?FUNCTION_NAME, [Opts]),
    case maybe_retry(Url, Retry) of
        error ->
            ok;
        {ok, Res} ->
            ok = persistent_term:put(?CACHE_TOPSTORIES, lists:sublist(Res, Total))
    end.

-spec maybe_retry(Url :: list(), Retry :: integer()) -> {ok, Res :: list()} | error.
maybe_retry(_, 0) ->
    error;
maybe_retry(Url, Retry) ->
    try 
        {ok, {{_, 200, _}, _, Body}} = httpc:request(Url),
        Res = jiffy:decode(Body),
        {ok, Res}
    catch
        _:_ ->
            maybe_retry(Url, Retry - 1)
    end.
