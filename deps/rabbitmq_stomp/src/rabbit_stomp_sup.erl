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
%% Copyright (c) 2007-2015 Pivotal Software, Inc.  All rights reserved.
%%

-module(rabbit_stomp_sup).
-behaviour(supervisor).

-export([start_link/2, init/1]).

start_link(Listeners, Configuration) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE,
                          [Listeners, Configuration]).

init([{Listeners, SslListeners0}, Configuration]) ->
    {ok, SocketOpts} = application:get_env(rabbitmq_stomp, tcp_listen_options),
    {SslOpts, SslListeners}
        = case SslListeners0 of
              [] -> {none, []};
              _  -> {rabbit_networking:ensure_ssl(),
                     case rabbit_networking:poodle_check('STOMP') of
                         ok     -> SslListeners0;
                         danger -> []
                     end}
          end,
    {ok, {{one_for_all, 10, 10},
           listener_specs(fun tcp_listener_spec/1,
                          [SocketOpts, Configuration], Listeners) ++
           listener_specs(fun ssl_listener_spec/1,
                          [SocketOpts, SslOpts, Configuration], SslListeners)}}.

listener_specs(Fun, Args, Listeners) ->
    [Fun([Address | Args]) ||
        Listener <- Listeners,
        Address  <- rabbit_networking:tcp_listener_addresses(Listener)].

tcp_listener_spec([Address, SocketOpts, Configuration]) ->
    rabbit_networking:tcp_listener_spec(
      rabbit_stomp_listener_sup, Address, SocketOpts,
      ranch_tcp, rabbit_stomp_client_sup, Configuration,
      stomp, "STOMP TCP Listener").

ssl_listener_spec([Address, SocketOpts, SslOpts, Configuration]) ->
    rabbit_networking:tcp_listener_spec(
      rabbit_stomp_listener_sup, Address, SocketOpts ++ SslOpts,
      ranch_ssl, rabbit_stomp_client_sup, Configuration,
      'stomp/ssl', "STOMP SSL Listener").