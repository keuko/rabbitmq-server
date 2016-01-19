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
%% The Original Code is RabbitMQ Sharding Plugin
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2011-2015 GoPivotal, Inc.  All rights reserved.
%%

-module(rabbit_sharding_test_util).

-include_lib("eunit/include/eunit.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-compile(export_all).

set_param(Component, Name, Value) ->
    rabbitmqctl(fmt("set_parameter ~s ~s '~s'", [Component, Name, Value])).

clear_param(Component, Name) ->
    rabbitmqctl(fmt("clear_parameter ~s ~s", [Component, Name])).

set_pol(Name, Pattern, Defn) ->
    rabbitmqctl(fmt("set_policy ~s \"~s\" '~s'", [Name, Pattern, Defn])).

clear_pol(Name) ->
    rabbitmqctl(fmt("clear_policy ~s ", [Name])).

fmt(Fmt, Args) ->
    string:join(string:tokens(rabbit_misc:format(Fmt, Args), [$\n]), " ").

start_other_node({Name, Port}) ->
    start_other_node({Name, Port}, "rabbit-" ++ Name).

start_other_node({Name, Port}, Config) ->
    start_other_node({Name, Port}, Config,
                     os:getenv("RABBITMQ_ENABLED_PLUGINS_FILE")).

start_other_node({Name, Port}, Config, PluginsFile) ->
    make("OTHER_NODE=" ++ Name ++
         " OTHER_PORT=" ++ integer_to_list(Port) ++
         " OTHER_CONFIG=" ++ Config ++
         " OTHER_PLUGINS=" ++ PluginsFile ++
         " start-other-node").

stop_other_node({Name, _Port}) ->
    make("OTHER_NODE=" ++ Name ++
         " stop-other-node").

reset_other_node({Name, _Port}) ->
    make("OTHER_NODE=" ++ Name ++
         " reset-other-node").

cluster_other_node({Name, _Port}, {MainName, _Port2}) ->
    make("OTHER_NODE=" ++ Name ++
         " MAIN_NODE=" ++ atom_to_list(n(MainName)) ++
         " cluster-other-node").

make(Args) ->
    Make = case os:getenv("MAKE") of
        false -> "make";
        M     -> M
    end,
    execute(Make ++ " " ++ Args),
    timer:sleep(1000).

rabbitmqctl(Args) ->
    execute(os:getenv("RABBITMQCTL") ++ " " ++ Args),
    timer:sleep(100).

execute(Cmd) ->
    Res = os:cmd(Cmd ++ " ; echo $?"),
    case lists:reverse(string:tokens(Res, "\n")) of
        ["0" | _] -> ok;
        _         -> exit({command_failed, Cmd, Res})
    end.

xr(Name) -> rabbit_misc:r(<<"/">>, exchange, Name).
qr(Name) -> rabbit_misc:r(<<"/">>, queue, Name).

n(Nodename) ->
    {_, NodeHost} = rabbit_nodes:parts(node()),
    rabbit_nodes:make({Nodename, NodeHost}).
