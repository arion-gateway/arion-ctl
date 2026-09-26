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

defmodule Arion.ControlPlane.Helpers.Listener do
  @moduledoc """
  Listeners: a socket address with its filter chains, listener filters and
  socket options. `add_*` accumulates in call order; `put_filter_chains/2`
  replaces the chains.
  """

  alias Arion.ControlPlane.Helpers.{Endpoint, Xds}
  alias Arion.ControlPlane.Pb
  alias Arion.ControlPlane.Pb.Listener.Listener

  @type listener :: Listener.t()

  @spec new(String.t(), Pb.Data.Address.t(), keyword()) :: listener
  def new(name, address, opts \\ []),
    do: %Listener{name: name, address: address, stat_prefix: Keyword.get(opts, :stat_prefix, "")}

  def local_address(port, address \\ "0.0.0.0"), do: Endpoint.address(address, port)

  @doc "Adds a filter chain; the proxy picks the chain whose match is most specific."
  @spec add_filter_chain(listener, Pb.Listener.FilterChain.t()) :: listener
  def add_filter_chain(%Listener{filter_chains: chains} = listener, chain),
    do: %{listener | filter_chains: chains ++ [chain]}

  @spec put_filter_chains(listener, [Pb.Listener.FilterChain.t()]) :: listener
  def put_filter_chains(%Listener{} = listener, chains) when is_list(chains),
    do: %{listener | filter_chains: chains}

  @doc "Adds a listener filter, run before the chain is chosen, in call order."
  @spec add_listener_filter(listener, Pb.Listener.ListenerFilter.t()) :: listener
  def add_listener_filter(%Listener{listener_filters: filters} = listener, filter),
    do: %{listener | listener_filters: filters ++ [filter]}

  @spec add_socket_option(listener, Pb.Data.SocketOption.t()) :: listener
  def add_socket_option(%Listener{socket_options: options} = listener, option),
    do: %{listener | socket_options: options ++ [option]}

  def tls_inspector do
    Xds.listener_filter(
      "envoy.filters.listener.tls_inspector",
      :tls_inspector,
      %Pb.Data.Extensions.TlsInspector{enable_ja3_fingerprinting: false}
    )
  end

  @doc "A connection rate limit of `max_tokens`, refilled by `tokens_per_fill` every `fill_interval` seconds."
  def local_rate_limit(stat_prefix, max_tokens, tokens_per_fill, fill_interval) do
    config = %Pb.Data.Extensions.ListenerLocalRateLimit{
      stat_prefix: stat_prefix,
      token_bucket: Xds.token_bucket(max_tokens, tokens_per_fill, fill_interval)
    }

    Xds.listener_filter(
      "envoy.filters.listener.local_ratelimit",
      :listener_local_rate_limit,
      config
    )
  end
end
