%%%----------------------------------------------------------------------
%%% File    : mod_adhoc.erl
%%% Author  : Magnus Henoch <henoch@dtek.chalmers.se>
%%% Purpose : Handle incoming ad-doc requests (XEP-0050)
%%% Created : 15 Nov 2005 by Magnus Henoch <henoch@dtek.chalmers.se>
%%%
%%%
%%% ejabberd, Copyright (C) 2002-2011   ProcessOne
%%%
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with this program; if not, write to the Free Software
%%% Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
%%%
%%%----------------------------------------------------------------------
-module(mod_adhoc).
-author('henoch@dtek.chalmers.se').

-behaviour(gen_mod).
-behaviour(mongoose_module_metrics).

-type command_hook_acc() :: {error, exml:element()} | exml:element() | ignore | empty.
-export_type([command_hook_acc/0]).

-export([start/2,
         stop/1,
         config_spec/0,
         process_local_iq/4,
         process_sm_iq/4,
         get_local_commands/5,
         get_local_identity/5,
         get_local_features/5,
         get_sm_commands/5,
         get_sm_identity/5,
         get_sm_features/5,
         ping_item/4,
         ping_command/4]).

-include("mongoose.hrl").
-include("jlib.hrl").
-include("adhoc.hrl").
-include("mongoose_config_spec.hrl").

start(Host, Opts) ->
    IQDisc = gen_mod:get_opt(iqdisc, Opts, one_queue),

    gen_iq_handler:add_iq_handler(ejabberd_local, Host, ?NS_COMMANDS,
                                  ?MODULE, process_local_iq, IQDisc),
    gen_iq_handler:add_iq_handler(ejabberd_sm, Host, ?NS_COMMANDS,
                                  ?MODULE, process_sm_iq, IQDisc),
    ejabberd_hooks:add(hooks(Host)).

stop(Host) ->
    ejabberd_hooks:delete(hooks(Host)),

    gen_iq_handler:remove_iq_handler(ejabberd_sm, Host, ?NS_COMMANDS),
    gen_iq_handler:remove_iq_handler(ejabberd_local, Host, ?NS_COMMANDS).

hooks(Host) ->
    [{disco_local_identity, Host, ?MODULE, get_local_identity, 99},
     {disco_local_features, Host, ?MODULE, get_local_features, 99},
     {disco_local_items, Host, ?MODULE, get_local_commands, 99},
     {disco_sm_identity, Host, ?MODULE, get_sm_identity, 99},
     {disco_sm_features, Host, ?MODULE, get_sm_features, 99},
     {disco_sm_items, Host, ?MODULE, get_sm_commands, 99},
     {adhoc_local_items, Host, ?MODULE, ping_item, 100},
     {adhoc_local_commands, Host, ?MODULE, ping_command, 100}].

-spec config_spec() -> mongoose_config_spec:config_section().
config_spec() ->
    #section{
       items = #{<<"report_commands_node">> => #option{type = boolean},
                 <<"iqdisc">> => mongoose_config_spec:iqdisc()}
      }.

%%-------------------------------------------------------------------------

-spec get_local_commands(Acc :: {result, [exml:element()]} | {error, any()} | empty,
                         From :: jid:jid(),
                         To :: jid:jid(),
                         NS :: binary(),
                         ejabberd:lang()) -> {result, [exml:element()]} | {error, any()} | empty.
get_local_commands(Acc, _From, #jid{lserver = LServer} = _To, <<"">>, Lang) ->
    Display = gen_mod:get_module_opt(LServer, ?MODULE, report_commands_node, false),
    case Display of
        false ->
            Acc;
        _ ->
            Items = case Acc of
                        {result, I} -> I;
                        _ -> []
                    end,
            Nodes = [#xmlel{name = <<"item">>,
                            attrs = [{<<"jid">>, LServer},
                                     {<<"node">>, ?NS_COMMANDS},
                                     {<<"name">>, translate:translate(Lang, <<"Commands">>)}]}],
            {result, Items ++ Nodes}
    end;
get_local_commands(_Acc, From, #jid{lserver = LServer} = To, ?NS_COMMANDS, Lang) ->
    mongoose_hooks:adhoc_local_items(LServer, From, To, Lang);
get_local_commands(_Acc, _From, _To, <<"ping">>, _Lang) ->
    {result, []};
get_local_commands(Acc, _From, _To, _Node, _Lang) ->
    Acc.

%%-------------------------------------------------------------------------

-spec get_sm_commands(Acc :: [exml:element()],
                      From :: jid:jid(),
                      To :: jid:jid(),
                      NS :: binary(),
                      ejabberd:lang()) -> {result, [exml:element()]} | [exml:element()].
get_sm_commands(Acc, _From, #jid{lserver = LServer} = To, <<"">>, Lang) ->
    Display = gen_mod:get_module_opt(LServer, ?MODULE, report_commands_node, false),
    case Display of
        false ->
            Acc;
        _ ->
            Items = case Acc of
                        {result, I} -> I;
                        _ -> []
                    end,
            Nodes = [#xmlel{name = <<"item">>,
                            attrs = [{<<"jid">>, jid:to_binary(To)},
                                     {<<"node">>, ?NS_COMMANDS},
                                     {<<"name">>, translate:translate(Lang, <<"Commands">>)}]}],
            {result, Items ++ Nodes}
    end;

get_sm_commands(_Acc, From, #jid{lserver = LServer} = To, ?NS_COMMANDS, Lang) ->
    mongoose_hooks:adhoc_sm_items(LServer, From, To, Lang);

get_sm_commands(Acc, _From, _To, _Node, _Lang) ->
    Acc.

%%-------------------------------------------------------------------------

%% @doc On disco info request to the ad-hoc node, return automation/command-list.
-spec get_local_identity(Acc :: [exml:element()],
                         From :: jid:jid(),
                         To :: jid:jid(),
                         NS :: binary(),
                         ejabberd:lang()) -> [exml:element()].
get_local_identity(Acc, _From, _To, ?NS_COMMANDS, Lang) ->
    [#xmlel{name = <<"identity">>,
            attrs = [{<<"category">>, <<"automation">>},
                     {<<"type">>, <<"command-list">>},
                     {<<"name">>, translate:translate(Lang, <<"Commands">>)}]} | Acc];
get_local_identity(Acc, _From, _To, <<"ping">>, Lang) ->
    [#xmlel{name = <<"identity">>,
            attrs = [{<<"category">>, <<"automation">>},
                     {<<"type">>, <<"command-node">>},
                     {<<"name">>, translate:translate(Lang, <<"Ping">>)}]} | Acc];
get_local_identity(Acc, _From, _To, _Node, _Lang) ->
    Acc.

%%-------------------------------------------------------------------------

%% @doc On disco info request to the ad-hoc node, return automation/command-list.
-spec get_sm_identity(Acc :: [exml:element()],
                     From :: jid:jid(),
                     To :: jid:jid(),
                     NS :: binary(),
                     ejabberd:lang()) -> [exml:element()].
get_sm_identity(Acc, _From, _To, ?NS_COMMANDS, Lang) ->
    [#xmlel{name = <<"identity">>,
            attrs = [{<<"category">>, <<"automation">>},
                     {<<"type">>, <<"command-list">>},
                     {<<"name">>, translate:translate(Lang, <<"Commands">>)}]} | Acc];
get_sm_identity(Acc, _From, _To, _Node, _Lang) ->
    Acc.

%%-------------------------------------------------------------------------

-spec get_local_features(Acc :: {result, [exml:element()]} | empty | {error, any()},
                         From :: jid:jid(),
                         To :: jid:jid(),
                         NS :: binary(),
                         ejabberd:lang()) -> {result, [exml:element()]} | {error, any()}.
get_local_features(Acc, _From, _To, <<"">>, _Lang) ->
    Feats = case Acc of
                {result, I} -> I;
                _ -> []
            end,
    {result, Feats ++ [?NS_COMMANDS]};
get_local_features(_Acc, _From, _To, ?NS_COMMANDS, _Lang) ->
    %% override all lesser features...
    {result, []};
get_local_features(_Acc, _From, _To, <<"ping">>, _Lang) ->
    %% override all lesser features...
    {result, [?NS_COMMANDS]};
get_local_features(Acc, _From, _To, _Node, _Lang) ->
    Acc.

%%-------------------------------------------------------------------------

-spec get_sm_features(Acc :: {result, [exml:element()]} | {error, any()} | empty,
                             From :: jid:jid(),
                             To :: jid:jid(),
                             NS :: binary(),
                             ejabberd:lang()) -> {result, [exml:element()]} | {error, any()} | empty.
get_sm_features(Acc, _From, _To, <<"">>, _Lang) ->
    Feats = case Acc of
                {result, I} -> I;
                _ -> []
            end,
    {result, Feats ++ [?NS_COMMANDS]};
get_sm_features(_Acc, _From, _To, ?NS_COMMANDS, _Lang) ->
    %% override all lesser features...
    {result, []};
get_sm_features(Acc, _From, _To, _Node, _Lang) ->
    Acc.

%%-------------------------------------------------------------------------

-spec process_local_iq(jid:jid(), jid:jid(), mongoose_acc:t(), jlib:iq()) ->
    {mongoose_acc:t(), ignore | jlib:iq()}.
process_local_iq(From, To, Acc, IQ) ->
    {Acc, process_adhoc_request(From, To, IQ, adhoc_local_commands)}.

-spec process_sm_iq(jid:jid(), jid:jid(), mongoose_acc:t(), jlib:iq()) ->
    {mongoose_acc:t(), ignore | jlib:iq()}.
process_sm_iq(From, To, Acc, IQ) ->
    {Acc, process_adhoc_request(From, To, IQ, adhoc_sm_commands)}.

-spec process_adhoc_request(jid:jid(), jid:jid(), jlib:iq(),
        Hook :: atom()) -> ignore | jlib:iq().
process_adhoc_request(From, To, #iq{sub_el = SubEl} = IQ, Hook) ->
    ?LOG_DEBUG(#{what => adhoc_parse_request, iq => IQ, hook => Hook}),
    case adhoc:parse_request(IQ) of
        {error, Error} ->
            IQ#iq{type = error, sub_el = [SubEl, Error]};
        #adhoc_request{} = AdhocRequest ->
            Host = To#jid.lserver,
            case run_request_hook(Hook, Host, From, To, AdhocRequest) of
                ignore ->
                    ignore;
                empty ->
                    IQ#iq{type = error, sub_el = [SubEl, mongoose_xmpp_errors:item_not_found()]};
                {error, Error} ->
                    IQ#iq{type = error, sub_el = [SubEl, Error]};
                Command ->
                    IQ#iq{type = result, sub_el = [Command]}
            end
    end.

run_request_hook(adhoc_local_commands, Host, From, To, AdhocRequest) ->
    mongoose_hooks:adhoc_local_commands(Host, From, To, AdhocRequest);
run_request_hook(adhoc_sm_commands, Host, From, To, AdhocRequest) ->
    mongoose_hooks:adhoc_sm_commands(Host, From, To, AdhocRequest).

-spec ping_item(Acc :: {result, [exml:element()]},
                From :: jid:jid(),
                To :: jid:jid(),
                ejabberd:lang()) -> {result, [exml:element()]}.
ping_item(Acc, _From, #jid{lserver = Server} = _To, Lang) ->
    Items = case Acc of
                {result, I} ->
                    I;
                _ ->
                    []
            end,
    Nodes = [#xmlel{name = <<"item">>,
                    attrs = [{<<"jid">>, Server},
                             {<<"node">>, <<"ping">>},
                             {<<"name">>, translate:translate(Lang, <<"Ping">>)}]}],
    {result, Items ++ Nodes}.


-spec ping_command(Acc :: command_hook_acc(),
                   From :: jid:jid(),
                   To :: jid:jid(),
                   adhoc:request()) -> command_hook_acc().
ping_command(empty, _From, _To,
             #adhoc_request{lang = Lang,
                            node = <<"ping">> = Node,
                            session_id = SessionID,
                            action = Action}) ->
    case Action == <<"">> orelse Action == <<"execute">> of
        true ->
            adhoc:produce_response(
              #adhoc_response{lang = Lang,
                              node = Node,
                              session_id = SessionID,
                              status = completed,
                              notes = [{<<"info">>, translate:translate(Lang, <<"Pong">>)}]});
        false ->
            {error, mongoose_xmpp_errors:bad_request()}
    end;
ping_command(Acc, _From, _To, _Request) ->
    Acc.

