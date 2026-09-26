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

defmodule Arion.ControlPlane.Helpers.FilterChain do
  @moduledoc """
  Filter chains: the network filters a listener runs for connections matching
  the chain, with its transport socket. `add_*` appends in call order; the
  last network filter must be terminal, such as an HCM or TCP proxy.
  """

  alias Arion.ControlPlane.Helpers.Xds
  alias Arion.ControlPlane.Pb
  alias Arion.ControlPlane.Pb.Listener.{FilterChain, FilterChainMatch}

  @type chain :: FilterChain.t()

  @spec new(String.t()) :: chain
  def new(name \\ "gateway"), do: %FilterChain{name: name}

  @spec add_filter(chain, Pb.Listener.Filter.t()) :: chain
  def add_filter(%FilterChain{filters: filters} = chain, filter),
    do: %{chain | filters: filters ++ [filter]}

  @doc "Adds an HTTP connection manager as the chain's network filter."
  @spec add_hcm(chain, Pb.Filter.HttpConnectionManager.t(), String.t()) :: chain
  def add_hcm(
        %FilterChain{} = chain,
        hcm,
        name \\ "envoy.filters.network.http_connection_manager"
      ),
      do: add_filter(chain, Xds.network_filter(name, :http_connection_manager, hcm))

  @doc "Replaces the chain's match, such as `server_names/1`; no match takes every connection."
  @spec put_match(chain, FilterChainMatch.t() | nil) :: chain
  def put_match(%FilterChain{} = chain, match), do: %{chain | filter_chain_match: match}

  @spec server_names([String.t()]) :: FilterChainMatch.t()
  def server_names(names), do: %FilterChainMatch{server_names: names}

  @spec put_transport_socket(chain, Pb.Data.TransportSocket.t() | nil) :: chain
  def put_transport_socket(%FilterChain{} = chain, socket),
    do: %{chain | transport_socket: socket}
end
