-module(mod_hacker_news_SUITE).

-compile(export_all).

-include_lib("exml/include/exml.hrl").
-include_lib("common_test/include/ct.hrl").

%%--------------------------------------------------------------------
%% Suite configuration
%%--------------------------------------------------------------------
all() ->
    [{group, hacker_news}].

groups() ->
    G = [
         {hacker_news, [], all_tests()}
        ],
    ct_helper:repeat_all_until_all_ok(G).

all_tests() ->
    [get_topstories].

suite() ->
    escalus:suite().

init_per_suite(Config) ->
    mongoose_helper:inject_module(?MODULE),
    escalus:init_per_suite(Config).

end_per_suite(Config) ->
    escalus_fresh:clean(),
    escalus:end_per_suite(Config).

init_per_group(hacker_news, Config) ->
    Domain = ct:get_config({hosts, mim, domain}),
    Opts = [{topstories_url, "https://hacker-news.firebaseio.com/v0/topstories.json?print=pretty"},
            {topstories_total, 50},
            {topstories_interval, 300000},
            {topstories_retry, 10}],
    dynamic_modules:start(Domain, mod_hacker_news, Opts),
    Config.

end_per_group(_GroupName, Config) ->
    Domain = ct:get_config({hosts, mim, domain}),
    dynamic_modules:stop(Domain, mod_hacker_news),
    Config.

init_per_testcase(CaseName, Config) ->
    escalus:init_per_testcase(CaseName, Config).

end_per_testcase(CaseName, Config) ->
    escalus:end_per_testcase(CaseName, Config).

%%--------------------------------------------------------------------
%% GET topstories tests
%%--------------------------------------------------------------------
get_topstories(Config) ->
    escalus:fresh_story(Config, [{alice, 1}],
        fun(Alice) ->
                Req = #xmlel{name = <<"iq">>,
                             attrs = [{<<"type">>, <<"get">>},
                                      {<<"id">>, base16:encode(crypto:strong_rand_bytes(16))}],
                             children = [#xmlel{name = <<"query">>,
                                                attrs = [{<<"xmlns">>, <<"erlang-solutions.com:xmpp:hacker-news">>}]}
                ]},
                escalus_client:send(Alice, Req),
                Resp = escalus_client:wait_for_stanza(Alice),
                {value, Count} = metrics_helper:get_counter_value([mod_hacker_news, get_topstories_response]),
                true = Count >= 1,
                escalus:assert(is_iq_result, [Req], Resp)
        end).
