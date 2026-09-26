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

defmodule Arion.ControlPlane.Helpers.Hcm do
  @moduledoc """
  The HTTP connection manager: codec, routes and the ordered HTTP filters.

  The filter list always ends with exactly one router. `new/1` starts with it,
  `add_filter/2` inserts before it in call order, and `put_filters/2` replaces
  the list while checking that invariant. Durations are seconds; `nil` leaves a
  wrapper field unset.
  """

  import Arion.ControlPlane.Helpers.Xds, only: [duration: 1, bool: 1]

  alias Arion.ControlPlane.Helpers.Xds
  alias Arion.ControlPlane.Pb
  alias Arion.ControlPlane.Pb.Filter.HttpConnectionManager

  @type hcm :: HttpConnectionManager.t()
  @type filter :: Pb.Filter.HttpFilter.t()

  @router "envoy.filters.http.router"

  @doc "A manager with `:codec_type` (`:AUTO`), `:stat_prefix` and `:request_timeout` options."
  @spec new(keyword()) :: hcm
  def new(opts \\ []) do
    %HttpConnectionManager{
      codec_type: Keyword.get(opts, :codec_type, :AUTO),
      stat_prefix: Keyword.get(opts, :stat_prefix, "ingress-http"),
      http_filters: [router_filter()],
      request_timeout: duration(Keyword.get(opts, :request_timeout))
    }
  end

  @doc "Inline routes, replacing an RDS reference."
  @spec route_config(hcm, Pb.Route.RouteConfiguration.t()) :: hcm
  def route_config(%HttpConnectionManager{} = hcm, route_config),
    do: %{hcm | route_specifier: {:route_config, route_config}}

  @doc "Routes fetched by name over delta ADS from the named xDS cluster, replacing inline routes."
  @spec rds(hcm, String.t(), String.t()) :: hcm
  def rds(%HttpConnectionManager{} = hcm, route_config_name, xds_cluster_name) do
    rds = %Pb.Filter.Rds{
      route_config_name: route_config_name,
      config_source: Xds.ads_config_source(xds_cluster_name)
    }

    %{hcm | route_specifier: {:rds, rds}}
  end

  @doc "Adds an HTTP filter before the router, which stays last. Raises on a second router."
  @spec add_filter(hcm, filter) :: hcm
  def add_filter(%HttpConnectionManager{http_filters: filters} = hcm, filter),
    do: put_filters(hcm, insert_before_router(filters, filter))

  @doc "Replaces the filters, which must end with their one router, in the given order."
  @spec put_filters(hcm, [filter]) :: hcm
  def put_filters(%HttpConnectionManager{} = hcm, filters) when is_list(filters),
    do: %{hcm | http_filters: check_router!(filters)}

  @doc "Adds an access log; logs are written in call order."
  @spec add_access_log(hcm, Pb.Data.Extensions.AccessLog.t()) :: hcm
  def add_access_log(%HttpConnectionManager{access_log: logs} = hcm, access_log),
    do: %{hcm | access_log: logs ++ [access_log]}

  @spec tracing(hcm, HttpConnectionManager.Tracing.t() | nil) :: hcm
  def tracing(%HttpConnectionManager{} = hcm, tracing), do: %{hcm | tracing: tracing}

  @doc "Adds an upgrade type such as `:websocket`; call once per type."
  @spec add_upgrade(hcm, atom() | String.t(), boolean()) :: hcm
  def add_upgrade(%HttpConnectionManager{upgrade_configs: upgrades} = hcm, type, enabled \\ true) do
    upgrade = %HttpConnectionManager.UpgradeConfig{
      upgrade_type: to_string(type),
      enabled: bool(enabled)
    }

    %{hcm | upgrade_configs: upgrades ++ [upgrade]}
  end

  @doc "X-Forwarded-For handling; an omitted option keeps the current value."
  @spec xff(hcm, keyword()) :: hcm
  def xff(%HttpConnectionManager{} = hcm, opts \\ []) do
    %{
      hcm
      | use_remote_address:
          bool(Keyword.get(opts, :use_remote_address)) || hcm.use_remote_address,
        xff_num_trusted_hops: Keyword.get(opts, :trusted_hops, hcm.xff_num_trusted_hops),
        skip_xff_append: Keyword.get(opts, :skip_append, hcm.skip_xff_append)
    }
  end

  @doc "The terminal router filter every manager ends with."
  @spec router_filter() :: filter
  def router_filter,
    do: %Pb.Filter.HttpFilter{name: @router, config_type: Xds.typed_config(:router)}

  def opentelemetry_tracing(grpc_service, service_name) do
    provider = %Pb.Data.Extensions.OpenTelemetryConfig{
      grpc_service: grpc_service,
      service_name: service_name
    }

    %HttpConnectionManager.Tracing{
      provider: %HttpConnectionManager.Tracing.Provider{
        name: "envoy.tracers.opentelemetry",
        config_type: Xds.typed_config(:opentelemetry_tracing, provider)
      }
    }
  end

  defp check_router!(filters) do
    routers = Enum.count(filters, &router?/1)

    cond do
      routers != 1 ->
        raise ArgumentError, "http filters need exactly one router, got #{routers}"

      not router?(List.last(filters)) ->
        raise ArgumentError, "the router must be the last http filter"

      true ->
        filters
    end
  end

  defp router?(%Pb.Filter.HttpFilter{name: @router}), do: true
  defp router?(_filter), do: false

  defp insert_before_router([], filter), do: [filter, router_filter()]
  defp insert_before_router([%{name: @router} = router], filter), do: [filter, router]

  defp insert_before_router([head | tail], filter),
    do: [head | insert_before_router(tail, filter)]
end
