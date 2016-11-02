%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is Pivotal Software, Inc.
%% Copyright (c) 2013 Pivotal Software, Inc.  All rights reserved.
%%

-module(rjms_topic_selector_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").
-include("rabbit_jms_topic_exchange.hrl").

-import(rabbit_ct_client_helpers, [open_connection_and_channel/1,
                                   close_connection_and_channel/2]).

%% Useful test constructors
-define(BSELECTARG(BinStr), {?RJMS_COMPILED_SELECTOR_ARG, longstr, BinStr}).
-define(BASICMSG(Payload, Hdrs), #'amqp_msg'{props=#'P_basic'{headers=Hdrs}, payload=Payload}).
-define(VERSION_ARG, {?RJMS_VERSION_ARG, longstr, <<"1.4.7">>}).

all() ->
    [
      {group, parallel_tests}
    ].

groups() ->
    [
      {parallel_tests, [parallel], [
                                    test_topic_selection,
                                    test_default_topic_selection
                                   ]}
    ].

%% -------------------------------------------------------------------
%% Test suite setup/teardown.
%% -------------------------------------------------------------------

init_per_suite(Config) ->
    rabbit_ct_helpers:log_environment(),
    Config1 = rabbit_ct_helpers:set_config(Config, [
        {rmq_nodename_suffix, ?MODULE}
      ]),
    rabbit_ct_helpers:run_setup_steps(Config1,
      rabbit_ct_broker_helpers:setup_steps() ++
      rabbit_ct_client_helpers:setup_steps()).

end_per_suite(Config) ->
    rabbit_ct_helpers:run_teardown_steps(Config,
      rabbit_ct_client_helpers:teardown_steps() ++
      rabbit_ct_broker_helpers:teardown_steps()).

init_per_group(_, Config) ->
    Config.

end_per_group(_, Config) ->
    Config.

init_per_testcase(Testcase, Config) ->
    rabbit_ct_helpers:testcase_started(Config, Testcase).

end_per_testcase(Testcase, Config) ->
    rabbit_ct_helpers:testcase_finished(Config, Testcase).

%% -------------------------------------------------------------------
%% Test cases.
%% -------------------------------------------------------------------

test_topic_selection(Config) ->
    {Connection, Channel} = open_connection_and_channel(Config),

    Exchange = declare_rjms_exchange(Channel, "rjms_test_topic_selector_exchange", [?VERSION_ARG]),

    %% Declare a queue and bind it
    Q = declare_queue(Channel),
    bind_queue(Channel, Q, Exchange, <<"select-key">>, [?BSELECTARG(<<"{ident, <<\"boolVal\">>}.">>), ?VERSION_ARG]),

    publish_two_messages(Channel, Exchange, <<"select-key">>),

    get_and_check(Channel, Q, 0, <<"true">>),

    close_connection_and_channel(Connection, Channel),
    ok.

test_default_topic_selection(Config) ->
    {Connection, Channel} = open_connection_and_channel(Config),

    Exchange = declare_rjms_exchange(Channel, "rjms_test_default_selector_exchange", [?VERSION_ARG]),

    %% Declare a queue and bind it
    Q = declare_queue(Channel),
    bind_queue(Channel, Q, Exchange, <<"select-key">>, [?BSELECTARG(<<"{ident, <<\"boolVal\">>}.">>), ?VERSION_ARG]),
    publish_two_messages(Channel, Exchange, <<"select-key">>),
    get_and_check(Channel, Q, 0, <<"true">>),

    close_connection_and_channel(Connection, Channel),
    ok.

%% Declare a rjms_topic_selector exchange, with args
declare_rjms_exchange(Ch, XNameStr, XArgs) ->
    Exchange = list_to_binary(XNameStr),
    Decl = #'exchange.declare'{ exchange = Exchange
                              , type = <<"x-jms-topic">>
                              , arguments = XArgs },
    #'exchange.declare_ok'{} = amqp_channel:call(Ch, Decl),
    Exchange.

%% Bind a selector queue to an exchange
bind_queue(Ch, Q, Ex, RKey, Args) ->
    Binding = #'queue.bind'{ queue       = Q
                           , exchange    = Ex
                           , routing_key = RKey
                           , arguments   = Args
                           },
    #'queue.bind_ok'{} = amqp_channel:call(Ch, Binding),
    ok.

%% Declare a queue, return Q name (as binary)
declare_queue(Ch) ->
    #'queue.declare_ok'{queue = Q} = amqp_channel:call(Ch, #'queue.declare'{}),
    Q.

%% Get message from Q and check remaining and payload.
get_and_check(Channel, Queue, ExpectedRemaining, ExpectedPayload) ->
    Get = #'basic.get'{queue = Queue},
    {#'basic.get_ok'{delivery_tag = Tag, message_count = Remaining}, Content}
      = amqp_channel:call(Channel, Get),
    amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = Tag}),

    ExpectedRemaining = Remaining,
    ExpectedPayload = Content#amqp_msg.payload,
    ok.

publish_two_messages(Chan, Exch, RoutingKey) ->
    Publish = #'basic.publish'{exchange = Exch, routing_key = RoutingKey},
    amqp_channel:cast(Chan, Publish, ?BASICMSG(<<"false">>, [{<<"boolVal">>, 'bool', false}])),
    amqp_channel:cast(Chan, Publish, ?BASICMSG(<<"true">>, [{<<"boolVal">>, 'bool', true}])),
    ok.
