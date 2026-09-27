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

defmodule Arion.ControlPlane.Helpers.ExtProc do
  @moduledoc """
  The external processing HTTP filter and its per-route overrides. Timeouts are
  seconds; an omitted option leaves its field unset.
  """

  import Arion.ControlPlane.Helpers.Xds, only: [duration: 1, bool: 1]

  alias Arion.ControlPlane.Helpers.Xds
  alias Arion.ControlPlane.Pb.Data.Extensions, as: Ext
  alias Arion.ControlPlane.Pb.Data.RegexMatcher

  def processor(grpc_service, opts \\ []) do
    %Ext.ExternalProcessor{
      grpc_service: grpc_service,
      failure_mode_allow: Keyword.get(opts, :failure_mode_allow, false),
      processing_mode: Keyword.get(opts, :processing_mode),
      message_timeout: duration(Keyword.get(opts, :message_timeout)),
      max_message_timeout: duration(Keyword.get(opts, :max_message_timeout)),
      mutation_rules: Keyword.get(opts, :mutation_rules),
      forward_rules: Keyword.get(opts, :forward_rules),
      allow_mode_override: Keyword.get(opts, :allow_mode_override, false),
      route_cache_action: Keyword.get(opts, :route_cache_action, :DEFAULT),
      observability_mode: Keyword.get(opts, :observability_mode, false),
      disable_immediate_response: Keyword.get(opts, :disable_immediate_response, false),
      metadata_options: Keyword.get(opts, :metadata_options),
      deferred_close_timeout: duration(Keyword.get(opts, :deferred_close_timeout)),
      send_body_without_waiting_for_header_response:
        Keyword.get(opts, :send_body_without_waiting_for_header_response, false),
      allowed_override_modes: Keyword.get(opts, :allowed_override_modes, [])
    }
  end

  def filter(name, processor), do: Xds.http_filter(name, :ext_proc, processor)

  def per_route_disabled, do: %Ext.ExtProcPerRoute{override: {:disabled, true}}

  def per_route_overrides(opts \\ []) do
    overrides = %Ext.ExtProcOverrides{
      processing_mode: Keyword.get(opts, :processing_mode),
      grpc_service: Keyword.get(opts, :grpc_service),
      failure_mode_allow: bool(Keyword.get(opts, :failure_mode_allow))
    }

    %Ext.ExtProcPerRoute{override: {:overrides, overrides}}
  end

  def processing_mode(opts \\ []) do
    %Ext.ProcessingMode{
      request_header_mode: Keyword.get(opts, :request_header_mode, :DEFAULT),
      response_header_mode: Keyword.get(opts, :response_header_mode, :DEFAULT),
      request_body_mode: Keyword.get(opts, :request_body_mode, :NONE),
      response_body_mode: Keyword.get(opts, :response_body_mode, :NONE),
      request_trailer_mode: Keyword.get(opts, :request_trailer_mode, :DEFAULT),
      response_trailer_mode: Keyword.get(opts, :response_trailer_mode, :DEFAULT)
    }
  end

  def mutation_rules(opts \\ []) do
    %Ext.HeaderMutationRules{
      allow_all_routing: bool(Keyword.get(opts, :allow_all_routing)),
      allow_envoy: bool(Keyword.get(opts, :allow_envoy)),
      disallow_system: bool(Keyword.get(opts, :disallow_system)),
      disallow_all: bool(Keyword.get(opts, :disallow_all)),
      allow_expression: regex(Keyword.get(opts, :allow_expression)),
      disallow_expression: regex(Keyword.get(opts, :disallow_expression)),
      disallow_is_error: bool(Keyword.get(opts, :disallow_is_error))
    }
  end

  def forward_rules(opts \\ []) do
    %Ext.HeaderForwardingRules{
      allowed_headers: list_matcher(Keyword.get(opts, :allowed_headers, [])),
      disallowed_headers: list_matcher(Keyword.get(opts, :disallowed_headers, []))
    }
  end

  def metadata_options(opts \\ []) do
    %Ext.MetadataOptions{
      forwarding_namespaces: %Ext.MetadataOptions.MetadataNamespaces{
        untyped: Keyword.get(opts, :forwarding_untyped, [])
      }
    }
  end

  defp list_matcher([]), do: nil
  defp list_matcher(matchers), do: %Ext.ListStringMatcher{patterns: matchers}

  defp regex(nil), do: nil
  defp regex(pattern), do: %RegexMatcher{regex: pattern}
end
