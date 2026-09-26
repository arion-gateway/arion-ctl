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

defmodule Arion.ControlPlane.Helpers.ProxyProtocol do
  @moduledoc "PROXY protocol on the listener side and towards upstreams."

  alias Arion.ControlPlane.Helpers.Xds
  alias Arion.ControlPlane.Pb.Data.Extensions, as: Ext

  def listener_filter(opts \\ []) do
    config = %Ext.ProxyProtocolListenerFilter{
      allow_requests_without_proxy_protocol: Keyword.get(opts, :allow_without_pp, false),
      stat_prefix: Keyword.get(opts, :stat_prefix, "proxy_protocol"),
      pass_through_tlvs: Keyword.get(opts, :pass_through_tlvs),
      disallowed_versions: Keyword.get(opts, :disallowed_versions, [])
    }

    Xds.listener_filter(
      "envoy.filters.listener.proxy_protocol",
      :proxy_protocol_listener_filter,
      config
    )
  end

  @doc "PROXY protocol towards upstreams, optionally wrapping an inner (TLS) transport socket."
  def transport_socket(inner_transport_socket \\ nil, proxy_config) do
    config = %Ext.ProxyProtocolUpstreamTransport{
      config: proxy_config,
      transport_socket: inner_transport_socket
    }

    Xds.transport_socket(
      "envoy.transport_sockets.upstream_proxy_protocol",
      :proxy_protocol_transport,
      config
    )
  end
end
