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

defmodule Arion.ControlPlane.Helpers.Xds do
  @moduledoc """
  Building blocks the resource helpers share: `Any` wrapping by registered
  kind, the typed-config wrappers for filters and transport sockets, the
  protobuf wrapper types, and the small messages many resources embed.
  Durations are seconds; `nil` leaves a wrapper field unset.
  """

  alias Arion.ControlPlane.Pb
  alias Arion.ControlPlane.Xds.ResourceTypes

  def type_url(kind), do: ResourceTypes.type_url!(kind)

  @doc """
  Wraps `message` into an `Any` under the wire URL of `kind`, which must be the
  registered module of that kind. The binary overload takes a literal type URL
  and checks nothing: it is the escape hatch for a type outside the registry.
  """
  def any(kind, message) when is_atom(kind) do
    ResourceTypes.check_module!(kind, message)
    any(type_url(kind), message)
  end

  def any(type_url, message) when is_binary(type_url),
    do: %Google.Protobuf.Any{type_url: type_url, value: Protobuf.encode(message)}

  def typed_config(kind) when is_atom(kind),
    do: {:typed_config, %Google.Protobuf.Any{type_url: type_url(kind)}}

  def typed_config(kind, message), do: {:typed_config, any(kind, message)}

  def typed_extension_config(kind, message, name \\ ""),
    do: %Pb.Data.TypedExtensionConfig{name: name, typed_config: any(kind, message)}

  def duration(nil), do: nil
  def duration(%Google.Protobuf.Duration{} = duration), do: duration
  def duration(seconds) when is_integer(seconds), do: %Google.Protobuf.Duration{seconds: seconds}

  def bool(nil), do: nil
  def bool(value) when is_boolean(value), do: %Google.Protobuf.BoolValue{value: value}

  def uint32(nil), do: nil
  def uint32(value) when is_integer(value), do: %Google.Protobuf.UInt32Value{value: value}

  def data_source(:filename, path), do: %Pb.Data.DataSource{specifier: {:filename, path}}

  def data_source(:inline_string, value),
    do: %Pb.Data.DataSource{specifier: {:inline_string, value}}

  def data_source(:inline_bytes, value),
    do: %Pb.Data.DataSource{specifier: {:inline_bytes, value}}

  def grpc_service(type, target, opts \\ [])

  def grpc_service(:envoy, cluster_name, opts) do
    %Pb.Data.GrpcService{
      target_specifier:
        {:envoy_grpc,
         %Pb.Data.GrpcService.EnvoyGrpc{
           cluster_name: cluster_name,
           max_receive_message_length: uint32(Keyword.get(opts, :max_receive_message_length))
         }},
      timeout: duration(Keyword.get(opts, :timeout))
    }
  end

  def grpc_service(:google, target_uri, opts) do
    %Pb.Data.GrpcService{
      target_specifier: {:google_grpc, %Pb.Data.GrpcService.GoogleGrpc{target_uri: target_uri}},
      timeout: duration(Keyword.get(opts, :timeout))
    }
  end

  @doc "Delta ADS over the named xDS cluster, for resources fetched by reference."
  def ads_config_source(cluster_name) do
    %Pb.Data.ConfigSource{
      config_source_specifier:
        {:api_config_source,
         %Pb.Data.ApiConfigSource{
           api_type: :AGGREGATED_DELTA_GRPC,
           grpc_services: [grpc_service(:envoy, cluster_name)]
         }}
    }
  end

  def transport_socket(name, kind, message),
    do: %Pb.Data.TransportSocket{name: name, config_type: typed_config(kind, message)}

  def network_filter(name, kind, message),
    do: %Pb.Listener.Filter{name: name, config_type: typed_config(kind, message)}

  def http_filter(name, kind, message),
    do: %Pb.Filter.HttpFilter{name: name, config_type: typed_config(kind, message)}

  def listener_filter(name, kind, message),
    do: %Pb.Listener.ListenerFilter{name: name, config_type: typed_config(kind, message)}

  def token_bucket(max_tokens, tokens_per_fill, fill_interval) do
    %Pb.Data.TokenBucket{
      max_tokens: max_tokens,
      tokens_per_fill: uint32(tokens_per_fill),
      fill_interval: duration(fill_interval)
    }
  end

  @doc "SO_BINDTODEVICE, binding a socket to a network interface."
  def bind_to_device(device_name) do
    %Pb.Data.SocketOption{
      description: "bind to interface",
      level: 1,
      name: 25,
      value: {:buf_value, device_name}
    }
  end
end
