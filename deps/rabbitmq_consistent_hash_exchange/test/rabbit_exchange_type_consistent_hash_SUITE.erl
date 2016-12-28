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
%% The Original Code is RabbitMQ Consistent Hash Exchange.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2007-2016 Pivotal Software, Inc.  All rights reserved.
%%

-module(rabbit_exchange_type_consistent_hash_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").
-include_lib("eunit/include/eunit.hrl").

all() ->
    [
      {group, non_parallel_tests}
    ].

groups() ->
    [
      {non_parallel_tests, [], [
                                routing_test
                               ]}
    ].

%% -------------------------------------------------------------------
%% Test suite setup/teardown
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
%% Test cases
%% -------------------------------------------------------------------

routing_test(Config) ->
    %% Run the test twice to test we clean up correctly
    routing_test0(Config, [<<"q0">>, <<"q1">>, <<"q2">>, <<"q3">>]),
    routing_test0(Config, [<<"q4">>, <<"q5">>, <<"q6">>, <<"q7">>]),

    passed.

routing_test0(Config, Qs) ->
    ok = test_with_rk(Config, Qs),
    ok = test_with_header(Config, Qs),
    ok = test_binding_with_negative_routing_key(Config),
    ok = test_binding_with_non_numeric_routing_key(Config),
    ok = test_with_correlation_id(Config, Qs),
    ok = test_with_message_id(Config, Qs),
    ok = test_with_timestamp(Config, Qs),
    ok = test_non_supported_property(Config),
    ok = test_mutually_exclusive_arguments(Config),
    ok.

%% -------------------------------------------------------------------
%% Implementation
%% -------------------------------------------------------------------

test_with_rk(Config, Qs) ->
    test0(Config, fun () ->
                  #'basic.publish'{exchange = <<"e">>, routing_key = rnd()}
          end,
          fun() ->
                  #amqp_msg{props = #'P_basic'{}, payload = <<>>}
          end, [], Qs).

test_with_header(Config, Qs) ->
    test0(Config, fun () ->
                  #'basic.publish'{exchange = <<"e">>}
          end,
          fun() ->
                  H = [{<<"hashme">>, longstr, rnd()}],
                  #amqp_msg{props = #'P_basic'{headers = H}, payload = <<>>}
          end, [{<<"hash-header">>, longstr, <<"hashme">>}], Qs).


test_with_correlation_id(Config, Qs) ->
    test0(Config, fun() ->
                  #'basic.publish'{exchange = <<"e">>}
          end,
          fun() ->
                  #amqp_msg{props = #'P_basic'{correlation_id = rnd()}, payload = <<>>}
          end, [{<<"hash-property">>, longstr, <<"correlation_id">>}], Qs).

test_with_message_id(Config, Qs) ->
    test0(Config, fun() ->
                  #'basic.publish'{exchange = <<"e">>}
          end,
          fun() ->
                  #amqp_msg{props = #'P_basic'{message_id = rnd()}, payload = <<>>}
          end, [{<<"hash-property">>, longstr, <<"message_id">>}], Qs).

test_with_timestamp(Config, Qs) ->
    test0(Config, fun() ->
                  #'basic.publish'{exchange = <<"e">>}
          end,
          fun() ->
                  #amqp_msg{props = #'P_basic'{timestamp = rndint()}, payload = <<>>}
          end, [{<<"hash-property">>, longstr, <<"timestamp">>}], Qs).

test_mutually_exclusive_arguments(Config) ->
    Chan = rabbit_ct_client_helpers:open_channel(Config, 0),

    process_flag(trap_exit, true),
    Cmd = #'exchange.declare'{
             exchange  = <<"fail">>,
             type      = <<"x-consistent-hash">>,
             arguments = [{<<"hash-header">>, longstr, <<"foo">>},
                          {<<"hash-property">>, longstr, <<"bar">>}]
            },
    ?assertExit(_, amqp_channel:call(Chan, Cmd)),

    rabbit_ct_client_helpers:close_channel(Chan),
    ok.

test_non_supported_property(Config) ->
    Chan = rabbit_ct_client_helpers:open_channel(Config, 0),

    process_flag(trap_exit, true),
    Cmd = #'exchange.declare'{
             exchange  = <<"fail">>,
             type      = <<"x-consistent-hash">>,
             arguments = [{<<"hash-property">>, longstr, <<"app_id">>}]
            },
    ?assertExit(_, amqp_channel:call(Chan, Cmd)),

    rabbit_ct_client_helpers:close_channel(Chan),
    ok.

rnd() ->
    list_to_binary(integer_to_list(rndint())).

rndint() ->
    rand_compat:uniform(1000000).

test0(Config, MakeMethod, MakeMsg, DeclareArgs, [Q1, Q2, Q3, Q4] = Queues) ->
    Count = 10000,
    Chan = rabbit_ct_client_helpers:open_channel(Config, 0),

    #'exchange.declare_ok'{} =
        amqp_channel:call(Chan,
                          #'exchange.declare' {
                            exchange = <<"e">>,
                            type = <<"x-consistent-hash">>,
                            auto_delete = true,
                            arguments = DeclareArgs
                          }),
    [#'queue.declare_ok'{} =
         amqp_channel:call(Chan, #'queue.declare' {
                             queue = Q, exclusive = true }) || Q <- Queues],
    [#'queue.bind_ok'{} =
         amqp_channel:call(Chan, #'queue.bind' {queue = Q,
                                                exchange = <<"e">>,
                                                routing_key = <<"10">>})
     || Q <- [Q1, Q2]],
    [#'queue.bind_ok'{} =
         amqp_channel:call(Chan, #'queue.bind' {queue = Q,
                                                exchange = <<"e">>,
                                                routing_key = <<"20">>})
     || Q <- [Q3, Q4]],
    #'tx.select_ok'{} = amqp_channel:call(Chan, #'tx.select'{}),
    [amqp_channel:call(Chan,
                       MakeMethod(),
                       MakeMsg()) || _ <- lists:duplicate(Count, const)],
    amqp_channel:call(Chan, #'tx.commit'{}),
    Counts =
        [begin
             #'queue.declare_ok'{message_count = M} =
                 amqp_channel:call(Chan, #'queue.declare' {queue     = Q,
                                                           exclusive = true}),
             M
         end || Q <- Queues],
    Count = lists:sum(Counts), %% All messages got routed
    [true = C > 0.01 * Count || C <- Counts], %% We are not *grossly* unfair
    amqp_channel:call(Chan, #'exchange.delete' {exchange = <<"e">>}),
    [amqp_channel:call(Chan, #'queue.delete' {queue = Q}) || Q <- Queues],

    rabbit_ct_client_helpers:close_channel(Chan),
    ok.

test_binding_with_negative_routing_key(Config) ->
    Chan = rabbit_ct_client_helpers:open_channel(Config, 0),

    Declare1 = #'exchange.declare'{exchange = <<"bind-fail">>,
                                   type = <<"x-consistent-hash">>},
    #'exchange.declare_ok'{} = amqp_channel:call(Chan, Declare1),
    Q = <<"test-queue">>,
    Declare2 = #'queue.declare'{queue = Q},
    #'queue.declare_ok'{} = amqp_channel:call(Chan, Declare2),
    process_flag(trap_exit, true),
    Cmd = #'queue.bind'{exchange = <<"bind-fail">>,
                        routing_key = <<"-1">>},
    ?assertExit(_, amqp_channel:call(Chan, Cmd)),
    Ch2 = rabbit_ct_client_helpers:open_channel(Config, 0),
    amqp_channel:call(Ch2, #'queue.delete'{queue = Q}),

    rabbit_ct_client_helpers:close_channel(Chan),
    rabbit_ct_client_helpers:close_channel(Ch2),
    ok.

test_binding_with_non_numeric_routing_key(Config) ->
    Chan = rabbit_ct_client_helpers:open_channel(Config, 0),

    Declare1 = #'exchange.declare'{exchange = <<"bind-fail">>,
                                   type = <<"x-consistent-hash">>},
    #'exchange.declare_ok'{} = amqp_channel:call(Chan, Declare1),
    Q = <<"test-queue">>,
    Declare2 = #'queue.declare'{queue = Q},
    #'queue.declare_ok'{} = amqp_channel:call(Chan, Declare2),
    process_flag(trap_exit, true),
    Cmd = #'queue.bind'{exchange = <<"bind-fail">>,
                        routing_key = <<"not-a-number">>},
    ?assertExit(_, amqp_channel:call(Chan, Cmd)),

    Ch2 = rabbit_ct_client_helpers:open_channel(Config, 0),
    amqp_channel:call(Ch2, #'queue.delete'{queue = Q}),

    rabbit_ct_client_helpers:close_channel(Chan),
    ok.
