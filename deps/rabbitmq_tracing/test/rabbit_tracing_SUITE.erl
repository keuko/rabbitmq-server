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
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2007-2016 Pivotal Software, Inc.  All rights reserved.
%%

-module(rabbit_tracing_SUITE).

-compile(export_all).

-define(LOG_DIR, "/var/tmp/rabbitmq-tracing/").

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").
-include_lib("rabbitmq_management/include/rabbit_mgmt_test.hrl").

-import(rabbit_misc, [pget/2]).

all() ->
    [
      {group, non_parallel_tests}
    ].

groups() ->
    [
      {non_parallel_tests, [], [
                                tracing_test,
                                tracing_validation_test
                               ]}
    ].

%% -------------------------------------------------------------------
%% Testsuite setup/teardown.
%% -------------------------------------------------------------------

init_per_suite(Config) ->
    rabbit_ct_helpers:log_environment(),
    %% initializes httpc
    inets:start(),
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
%% Testcases.
%% -------------------------------------------------------------------


tracing_test(Config) ->
    case filelib:is_dir(?LOG_DIR) of
        true -> {ok, Files} = file:list_dir(?LOG_DIR),
                [ok = file:delete(?LOG_DIR ++ F) || F <- Files];
        _    -> ok
    end,

    [] = http_get(Config, "/traces/%2f/"),
    [] = http_get(Config, "/trace-files/"),

    Args = [{format,  <<"json">>},
            {pattern, <<"#">>}],
    http_put(Config, "/traces/%2f/test", Args, ?NO_CONTENT),
    assert_list([[{name,    <<"test">>},
                  {format,  <<"json">>},
                  {pattern, <<"#">>}]], http_get(Config, "/traces/%2f/")),
    assert_item([{name,    <<"test">>},
                 {format,  <<"json">>},
                 {pattern, <<"#">>}], http_get(Config, "/traces/%2f/test")),

    Ch = rabbit_ct_client_helpers:open_channel(Config),
    amqp_channel:cast(Ch, #'basic.publish'{ exchange    = <<"amq.topic">>,
                                            routing_key = <<"key">> },
                      #amqp_msg{props   = #'P_basic'{},
                                payload = <<"Hello world">>}),

    rabbit_ct_client_helpers:close_channel(Ch),

    timer:sleep(100),

    http_delete(Config, "/traces/%2f/test", ?NO_CONTENT),
    [] = http_get(Config, "/traces/%2f/"),
    assert_list([[{name, <<"test.log">>}]], http_get(Config, "/trace-files/")),
    %% This is a bit cheeky as the log is actually one JSON doc per
    %% line and we assume here it's only one line
    assert_item([{type,         <<"published">>},
                 {exchange,     <<"amq.topic">>},
                 {routing_keys, [<<"key">>]},
                 {payload,      base64:encode(<<"Hello world">>)}],
                http_get(Config, "/trace-files/test.log")),
    http_delete(Config, "/trace-files/test.log", ?NO_CONTENT),

    passed.

tracing_validation_test(Config) ->
    Path = "/traces/%2f/test",
    http_put(Config, Path, [{pattern,           <<"#">>}],    ?BAD_REQUEST),
    http_put(Config, Path, [{format,            <<"json">>}], ?BAD_REQUEST),
    http_put(Config, Path, [{format,            <<"ebcdic">>},
                    {pattern,           <<"#">>}],    ?BAD_REQUEST),
    http_put(Config, Path, [{format,            <<"text">>},
                    {pattern,           <<"#">>},
                    {max_payload_bytes, <<"abc">>}],  ?BAD_REQUEST),
    http_put(Config, Path, [{format,            <<"json">>},
                    {pattern,           <<"#">>},
                    {max_payload_bytes, 1000}],       ?NO_CONTENT),
    http_delete(Config, Path, ?NO_CONTENT),

    passed.

%%---------------------------------------------------------------------------
%% TODO: Below is copied from rabbit_mgmt_test_http,
%%       should be moved to use rabbit_mgmt_test_util once rabbitmq_management
%%       is moved to Common Test

http_get(Config, Path) ->
    http_get(Config, Path, ?OK).

http_get(Config, Path, CodeExp) ->
    http_get(Config, Path, "guest", "guest", CodeExp).

http_get(Config, Path, User, Pass, CodeExp) ->
    {ok, {{_HTTP, CodeAct, _}, Headers, ResBody}} =
        req(Config, get, Path, [auth_header(User, Pass)]),
    assert_code(CodeExp, CodeAct, "GET", Path, ResBody),
    decode(CodeExp, Headers, ResBody).

http_put(Config, Path, List, CodeExp) ->
    http_put_raw(Config, Path, format_for_upload(List), CodeExp).

format_for_upload(List) ->
    iolist_to_binary(mochijson2:encode({struct, List})).

http_put_raw(Config, Path, Body, CodeExp) ->
    http_upload_raw(Config, put, Path, Body, "guest", "guest", CodeExp).

http_upload_raw(Config, Type, Path, Body, User, Pass, CodeExp) ->
    {ok, {{_HTTP, CodeAct, _}, Headers, ResBody}} =
        req(Config, Type, Path, [auth_header(User, Pass)], Body),
    assert_code(CodeExp, CodeAct, Type, Path, ResBody),
    decode(CodeExp, Headers, ResBody).

http_delete(Config, Path, CodeExp) ->
    http_delete(Config, Path, "guest", "guest", CodeExp).

http_delete(Config, Path, User, Pass, CodeExp) ->
    {ok, {{_HTTP, CodeAct, _}, Headers, ResBody}} =
        req(Config, delete, Path, [auth_header(User, Pass)]),
    assert_code(CodeExp, CodeAct, "DELETE", Path, ResBody),
    decode(CodeExp, Headers, ResBody).

assert_code(CodeExp, CodeAct, Type, Path, Body) ->
    case CodeExp of
        CodeAct -> ok;
        _       -> throw({expected, CodeExp, got, CodeAct, type, Type,
                          path, Path, body, Body})
    end.

mgmt_port(Config) ->
    config_port(Config, tcp_port_mgmt).

config_port(Config, PortKey) ->
    rabbit_ct_broker_helpers:get_node_config(Config, 0, PortKey).

uri_base_from(Config) ->
    binary_to_list(
      rabbit_mgmt_format:print(
        "http://localhost:~w/api",
        [mgmt_port(Config)])).

req(Config, Type, Path, Headers) ->
    httpc:request(Type, {uri_base_from(Config) ++ Path, Headers}, ?HTTPC_OPTS, []).

req(Config, Type, Path, Headers, Body) ->
    httpc:request(Type, {uri_base_from(Config) ++ Path, Headers, "application/json", Body},
                  ?HTTPC_OPTS, []).

decode(?OK, _Headers,  ResBody) -> cleanup(mochijson2:decode(ResBody));
decode(_,    Headers, _ResBody) -> Headers.

cleanup(L) when is_list(L) ->
    [cleanup(I) || I <- L];
cleanup({struct, I}) ->
    cleanup(I);
cleanup({K, V}) when is_binary(K) ->
    {list_to_atom(binary_to_list(K)), cleanup(V)};
cleanup(I) ->
    I.

auth_header(Username, Password) ->
    {"Authorization",
     "Basic " ++ binary_to_list(base64:encode(Username ++ ":" ++ Password))}.

%%---------------------------------------------------------------------------

assert_list(Exp, Act) ->
    case length(Exp) == length(Act) of
        true  -> ok;
        false -> throw({expected, Exp, actual, Act})
    end,
    [case length(lists:filter(fun(ActI) -> test_item(ExpI, ActI) end, Act)) of
         1 -> ok;
         N -> throw({found, N, ExpI, in, Act})
     end || ExpI <- Exp].

assert_item(Exp, Act) ->
    case test_item0(Exp, Act) of
        [] -> ok;
        Or -> throw(Or)
    end.

test_item(Exp, Act) ->
    case test_item0(Exp, Act) of
        [] -> true;
        _  -> false
    end.

test_item0(Exp, Act) ->
    [{did_not_find, ExpI, in, Act} || ExpI <- Exp,
                                      not lists:member(ExpI, Act)].
