# Copyright 2026 The arion-gateway Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule Arion.ControlPlane.Helpers.RateLimit do
  @moduledoc """
  Rate and connection limits as HTTP, listener and network filters. Token
  buckets refill `tokens_per_fill` every `fill_interval` seconds.
  """

  import Arion.ControlPlane.Helpers.Xds, only: [duration: 1]

  alias Arion.ControlPlane.Helpers.{Listener, Route, Xds}
  alias Arion.ControlPlane.Pb.Data.Extensions, as: Ext

  def local(max_tokens, tokens_per_fill, fill_interval, opts \\ []) do
    %Ext.LocalRateLimit{
      stat_prefix: Keyword.get(opts, :stat_prefix, "http-local-rate-limit"),
      token_bucket: Xds.token_bucket(max_tokens, tokens_per_fill, fill_interval),
      local_rate_limit_per_downstream_connection:
        Keyword.get(opts, :per_downstream_connection, false)
    }
  end

  def http_filter(name, local_rate_limit),
    do: Xds.http_filter(name, :local_rate_limit, local_rate_limit)

  @doc "Sets the route's limit for the local rate limit filter of that name."
  def per_route(route, filter_name, local_rate_limit),
    do: Route.put_per_filter_config(route, filter_name, :local_rate_limit, local_rate_limit)

  def listener_filter(stat_prefix, max_tokens, tokens_per_fill, fill_interval),
    do: Listener.local_rate_limit(stat_prefix, max_tokens, tokens_per_fill, fill_interval)

  def connection_limit_filter(name, stat_prefix, max_connections, opts \\ []) do
    config = %Ext.ConnectionLimit{
      stat_prefix: stat_prefix,
      max_connections: %Google.Protobuf.UInt64Value{value: max_connections},
      delay: duration(Keyword.get(opts, :delay))
    }

    Xds.network_filter(name, :network_connection_limit, config)
  end

  def network_rate_limit_filter(name, stat_prefix, grpc_service, descriptors, opts \\ []) do
    config = %Ext.NetworkRateLimit{
      stat_prefix: stat_prefix,
      domain: Keyword.get(opts, :domain, ""),
      descriptors: descriptors,
      failure_mode_deny: Keyword.get(opts, :failure_mode_deny, false),
      rate_limit_service: %Ext.RateLimitServiceConfig{grpc_service: grpc_service}
    }

    Xds.network_filter(name, :network_rate_limit, config)
  end

  def user_limiter(user_id_header_name, limits, opts \\ []) when is_list(limits) do
    %Ext.UserRateLimiter{
      user_id_header_name: user_id_header_name,
      stat_prefix: Keyword.get(opts, :stat_prefix, "user-rate-limit"),
      status: Keyword.get(opts, :status),
      user_rate_limits: limits
    }
  end

  def user_filter(name, user_limiter), do: Xds.http_filter(name, :user_rate_limiter, user_limiter)

  def user_limit(user_id, {:simple, max_tokens, rate}) do
    %Ext.UserRateLimit{
      user_id: user_id,
      limit: {:simple_rate_limit, %Ext.SimpleRateLimit{max_tokens: max_tokens, rate: rate}}
    }
  end

  def user_limit(user_id, %Ext.LocalRateLimit{} = local_rate_limit),
    do: %Ext.UserRateLimit{user_id: user_id, limit: {:local_rate_limit, local_rate_limit}}

  def descriptor(entries) do
    %Ext.RateLimitDescriptor{
      entries:
        Enum.map(entries, fn {key, value} ->
          %Ext.RateLimitDescriptor.Entry{key: key, value: value}
        end)
    }
  end
end
