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

defmodule Arion.ControlPlane.Helpers.Cluster do
  @moduledoc """
  Clusters: how upstream hosts are discovered, balanced and connected to.

  Constructors take the common options `:connect_timeout` (seconds, default
  5), `:lb_policy` (default `:ROUND_ROBIN`) and `:discovery`. `add_*`
  accumulates in call order; `put_*` replaces a field.
  """

  import Arion.ControlPlane.Helpers.Xds, only: [duration: 1, uint32: 1]

  alias Arion.ControlPlane.Helpers.{Endpoint, Xds}
  alias Arion.ControlPlane.Pb

  @lb_policy %{
    round_robin: :ROUND_ROBIN,
    random: :RANDOM,
    least_request: :LEAST_REQUEST,
    ring_hash: :RING_HASH,
    maglev: :MAGLEV,
    cluster_provided: :CLUSTER_PROVIDED
  }

  @lb_config %{
    round_robin: {Pb.Data.Extensions.RoundRobin, :lb_round_robin},
    random: {Pb.Data.Extensions.Random, :lb_random},
    least_request: {Pb.Data.Extensions.LeastRequest, :lb_least_request},
    ring_hash: {Pb.Data.Extensions.RingHash, :lb_ring_hash},
    maglev: {Pb.Data.Extensions.Maglev, :lb_maglev}
  }

  @type cluster :: Pb.Cluster.Cluster.t()

  def gen_ports(start, range), do: Enum.map(range, &(start + &1))

  @doc "A cluster with the common options; `:discovery` is `:static`, `:strict_dns`, `:eds` or `:original_dst`."
  @spec new(String.t(), keyword()) :: cluster
  def new(name, opts \\ []) do
    %Pb.Cluster.Cluster{
      name: name,
      cluster_discovery_type: {:type, discovery_type(Keyword.get(opts, :discovery, :static))},
      lb_policy: Keyword.get(opts, :lb_policy, :ROUND_ROBIN),
      connect_timeout: duration(Keyword.get(opts, :connect_timeout, 5))
    }
  end

  def static(name, address, ports, opts \\ []) do
    name
    |> new(Keyword.put(opts, :discovery, :static))
    |> put_load_assignment(Endpoint.assignment(name, address, ports))
  end

  def strict_dns(name, address, ports, opts \\ []) do
    name
    |> new(Keyword.put(opts, :discovery, :strict_dns))
    |> put_load_assignment(Endpoint.assignment(name, address, ports))
  end

  # The current Arion proxy rejects eds_cluster_config and takes EDS over ADS:
  # for it, use new(name, discovery: :eds) and publish the assignment.
  def eds(name, eds_cluster_name, opts \\ []) do
    %{
      new(name, Keyword.put(opts, :discovery, :eds))
      | eds_cluster_config: %Pb.Cluster.Cluster.EdsClusterConfig{
          eds_config: Xds.ads_config_source(eds_cluster_name)
        }
    }
  end

  @doc """
  A cluster forwarding to the connection's original destination, or to the
  `:http_header_name` header when `:use_http_header` is set, optionally on
  `:upstream_port_override` or from `:metadata_key`. Takes the common options
  of `new/2`; its discovery and load balancing are necessarily
  `:original_dst` and `:CLUSTER_PROVIDED`.
  """
  @spec original_dst(String.t(), keyword()) :: cluster
  def original_dst(name, opts \\ []) do
    config = %Pb.Cluster.Cluster.OriginalDstLbConfig{
      use_http_header: Keyword.get(opts, :use_http_header, false),
      http_header_name: Keyword.get(opts, :http_header_name, ""),
      upstream_port_override: uint32(Keyword.get(opts, :upstream_port_override)),
      metadata_key: Keyword.get(opts, :metadata_key)
    }

    opts = Keyword.merge(opts, discovery: :original_dst, lb_policy: :CLUSTER_PROVIDED)
    %{new(name, opts) | lb_config: {:original_dst_lb_config, config}}
  end

  @doc "Adds an endpoint to the cluster's first locality, starting an assignment if needed."
  @spec add_endpoint(
          cluster,
          Pb.Endpoint.LbEndpoint.t() | {String.t(), non_neg_integer()},
          keyword()
        ) ::
          cluster
  def add_endpoint(cluster, endpoint, opts \\ [])

  def add_endpoint(%Pb.Cluster.Cluster{} = cluster, %Pb.Endpoint.LbEndpoint{} = endpoint, _opts) do
    assignment =
      case cluster.load_assignment do
        %{endpoints: [locality | rest]} = assignment ->
          %{
            assignment
            | endpoints: [%{locality | lb_endpoints: locality.lb_endpoints ++ [endpoint]} | rest]
          }

        _none ->
          Endpoint.assignment(cluster.name, [endpoint])
      end

    put_load_assignment(cluster, assignment)
  end

  def add_endpoint(%Pb.Cluster.Cluster{} = cluster, {address, port}, opts),
    do: add_endpoint(cluster, Endpoint.lb(address, port, opts))

  @spec put_load_assignment(cluster, Pb.Endpoint.ClusterLoadAssignment.t() | nil) :: cluster
  def put_load_assignment(%Pb.Cluster.Cluster{} = cluster, assignment),
    do: %{cluster | load_assignment: assignment}

  @doc """
  The load balancing policy: a policy atom such as `:least_request`, `{:typed,
  policy}` for its extension form, or `{:override_host_header, header,
  fallback}` to route to the host a header names.
  """
  @spec lb(cluster, atom() | {:typed, atom()} | {:override_host_header, String.t(), atom()}) ::
          cluster
  def lb(%Pb.Cluster.Cluster{} = cluster, policy) when is_atom(policy),
    do: %{cluster | lb_policy: Map.fetch!(@lb_policy, policy), load_balancing_policy: nil}

  def lb(%Pb.Cluster.Cluster{} = cluster, {:typed, policy}) when is_atom(policy) do
    {module, kind} = Map.fetch!(@lb_config, policy)
    typed_lb(cluster, kind, struct(module))
  end

  def lb(%Pb.Cluster.Cluster{} = cluster, {:override_host_header, header, fallback}) do
    override = %Pb.Data.Extensions.OverrideHost{
      override_host_sources: [%Pb.Data.Extensions.OverrideHost.OverrideHostSource{header: header}],
      fallback_policy: load_balancing_policy(fallback)
    }

    typed_lb(cluster, :lb_override_host, override)
  end

  def put_http_protocol_options(%Pb.Cluster.Cluster{} = cluster, options) do
    %{
      cluster
      | typed_extension_protocol_options: %{
          "envoy.extensions.upstreams.http.v3.HttpProtocolOptions" =>
            Xds.any(:http_protocol_options, options)
        }
    }
  end

  def http1_options,
    do: explicit_http_config({:http_protocol_options, %Pb.Data.Http1ProtocolOptions{}})

  def http2_options do
    explicit_http_config(
      {:http2_protocol_options,
       %Pb.Data.Http2ProtocolOptions{
         connection_keepalive: %Pb.Data.KeepaliveSettings{
           interval: duration(30),
           timeout: duration(5)
         }
       }}
    )
  end

  defp explicit_http_config(protocol_config) do
    %Pb.Data.Extensions.HttpProtocolOptions{
      upstream_protocol_options:
        {:explicit_http_config,
         %Pb.Data.Extensions.HttpProtocolOptions.ExplicitHttpConfig{
           protocol_config: protocol_config
         }}
    }
  end

  def put_transport_socket(%Pb.Cluster.Cluster{} = cluster, transport_socket),
    do: %{cluster | transport_socket: transport_socket}

  def put_bind_device(%Pb.Cluster.Cluster{} = cluster, device_name) do
    %{
      cluster
      | upstream_bind_config: %Pb.Data.BindConfig{
          socket_options: [Xds.bind_to_device(device_name)]
        }
    }
  end

  @spec add_health_check(cluster, Pb.Data.HealthCheck.t()) :: cluster
  def add_health_check(%Pb.Cluster.Cluster{health_checks: checks} = cluster, health_check),
    do: %{cluster | health_checks: checks ++ [health_check]}

  @doc "Replaces the circuit breakers with the given `threshold/1` list."
  @spec circuit_breakers(cluster, [Pb.Cluster.CircuitBreakers.Thresholds.t()]) :: cluster
  def circuit_breakers(%Pb.Cluster.Cluster{} = cluster, thresholds) when is_list(thresholds),
    do: %{cluster | circuit_breakers: %Pb.Cluster.CircuitBreakers{thresholds: thresholds}}

  def threshold(opts \\ []) do
    %Pb.Cluster.CircuitBreakers.Thresholds{
      priority: Keyword.get(opts, :priority, :DEFAULT),
      max_requests: uint32(Keyword.get(opts, :max_requests)),
      max_retries: uint32(Keyword.get(opts, :max_retries)),
      track_remaining: Keyword.get(opts, :track_remaining, false)
    }
  end

  def raw_buffer_socket,
    do:
      Xds.transport_socket(
        "envoy.transport_sockets.raw_buffer",
        :raw_buffer,
        %Pb.Data.Extensions.RawBuffer{}
      )

  def load_balancing_policy(policy) when is_atom(policy) do
    {module, kind} = Map.fetch!(@lb_config, policy)
    load_balancing_policy(kind, struct(module))
  end

  def load_balancing_policy(kind, message) do
    %Pb.Data.Extensions.LoadBalancingPolicy{
      policies: [
        %Pb.Data.Extensions.LoadBalancingPolicy.Policy{
          typed_extension_config: Xds.typed_extension_config(kind, message)
        }
      ]
    }
  end

  defp typed_lb(cluster, kind, message),
    do: %{cluster | load_balancing_policy: load_balancing_policy(kind, message)}

  defp discovery_type(:static), do: :STATIC
  defp discovery_type(:strict_dns), do: :STRICT_DNS
  defp discovery_type(:eds), do: :EDS
  defp discovery_type(:original_dst), do: :ORIGINAL_DST
end
