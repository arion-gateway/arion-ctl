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

defmodule Arion.ControlPlane.Helpers.Jwt do
  @moduledoc "The JWT authentication HTTP filter: providers, JWKS sources and requirement rules."

  import Arion.ControlPlane.Helpers.Xds, only: [duration: 1]

  alias Arion.ControlPlane.Helpers.Xds
  alias Arion.ControlPlane.Pb.Data.Extensions, as: Ext

  def authentication(providers \\ %{}, rules \\ []),
    do: %Ext.JwtAuthentication{providers: providers, rules: rules}

  def filter(name, authentication), do: Xds.http_filter(name, :jwt_authn, authentication)

  def provider(issuer, jwks, opts \\ []) do
    %Ext.JwtProvider{
      issuer: issuer,
      audiences: Keyword.get(opts, :audiences, []),
      subjects: Keyword.get(opts, :subjects),
      jwks_source_specifier: jwks,
      forward: Keyword.get(opts, :forward, false),
      from_headers: Keyword.get(opts, :from_headers, []),
      from_params: Keyword.get(opts, :from_params, []),
      from_cookies: Keyword.get(opts, :from_cookies, []),
      forward_payload_header: Keyword.get(opts, :forward_payload_header, ""),
      pad_forward_payload_header: Keyword.get(opts, :pad_forward_payload_header, false),
      payload_in_metadata: Keyword.get(opts, :payload_in_metadata, ""),
      header_in_metadata: Keyword.get(opts, :header_in_metadata, ""),
      failed_status_in_metadata: Keyword.get(opts, :failed_status_in_metadata, ""),
      clock_skew_seconds: Keyword.get(opts, :clock_skew_seconds, 0),
      clear_route_cache: Keyword.get(opts, :clear_route_cache, false),
      claim_to_headers: Keyword.get(opts, :claim_to_headers, [])
    }
  end

  def remote_jwks(uri, cluster, timeout, opts \\ []) do
    {:remote_jwks,
     %Ext.RemoteJwks{
       http_uri: %Ext.HttpUri{
         uri: uri,
         http_upstream_type: {:cluster, cluster},
         timeout: duration(timeout)
       },
       cache_duration: duration(Keyword.get(opts, :cache_duration, 600)),
       retry_policy: Keyword.get(opts, :retry_policy)
     }}
  end

  def local_jwks(type, value) when type in [:inline_string, :filename],
    do: {:local_jwks, Xds.data_source(type, value)}

  def from_header(name, value_prefix \\ ""),
    do: %Ext.JwtHeader{name: name, value_prefix: value_prefix}

  def claim_to_header(claim_name, header_name),
    do: %Ext.JwtClaimToHeader{claim_name: claim_name, header_name: header_name}

  def requires_provider(provider_name),
    do: %Ext.JwtRequirement{requires_type: {:provider_name, provider_name}}

  def rule(match, requirement),
    do: %Ext.RequirementRule{match: match, requirement_type: {:requires, requirement}}
end
