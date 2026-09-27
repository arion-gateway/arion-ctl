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

defmodule Arion.ControlPlane.Helpers.Tls do
  @moduledoc "Upstream and downstream TLS transport sockets, from SDS secrets or inline material."

  import Arion.ControlPlane.Helpers.Xds, only: [bool: 1]

  alias Arion.ControlPlane.Helpers.Xds
  alias Arion.ControlPlane.Pb.Data.Extensions, as: Ext

  @tls_socket "envoy.transport_sockets.tls"

  # Signs nothing and its key was discarded: the proxy requires a parseable
  # trusted_ca even though ACCEPT_UNTRUSTED never consults it.
  @placeholder_ca """
  -----BEGIN CERTIFICATE-----
  MIIBsjCCAVegAwIBAgIUYFAb+Po9yoagyXbrHL03AakjqUIwCgYIKoZIzj0EAwIw
  LTErMCkGA1UEAwwiYXJpb24gYWNjZXB0LXVudHJ1c3RlZCBwbGFjZWhvbGRlcjAg
  Fw0yNjA5MzAyMDQ5MDdaGA8yMTI2MDkwNjIwNDkwN1owLTErMCkGA1UEAwwiYXJp
  b24gYWNjZXB0LXVudHJ1c3RlZCBwbGFjZWhvbGRlcjBZMBMGByqGSM49AgEGCCqG
  SM49AwEHA0IABOyUtdvvD1zpbBw/rjeufRSidXqhvQ+Pp24mUWYCfOsPIweEvoOU
  EMm+MIj/aMWopQ3YpgLXvrvX5KgLVRM+E0yjUzBRMB0GA1UdDgQWBBSJJDjmcz/7
  Z0fIps9D7ZU9VNea7TAfBgNVHSMEGDAWgBSJJDjmcz/7Z0fIps9D7ZU9VNea7TAP
  BgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMCA0kAMEYCIQCBDyV03EyiYD4N4frw
  BIsdSTIV6VoGWtzVC8QlzklcGQIhANdVtxqA84GebJc0W/aDFKp3woBhxQzji8p4
  vjLW00hs
  -----END CERTIFICATE-----
  """

  def upstream_accept_untrusted(sni) do
    validation = %Ext.CertificateValidationContext{
      trusted_ca: Xds.data_source(:inline_string, @placeholder_ca),
      trust_chain_verification: :ACCEPT_UNTRUSTED
    }

    context = %Ext.UpstreamTlsContext{
      sni: sni,
      common_tls_context: %Ext.CommonTlsContext{
        validation_context_type: {:validation_context, validation}
      }
    }

    Xds.transport_socket(@tls_socket, :upstream_tls_context, context)
  end

  def upstream_sds_validation(secret_name, opts \\ []) do
    context = %Ext.UpstreamTlsContext{
      sni: Keyword.get(opts, :sni, ""),
      common_tls_context: %Ext.CommonTlsContext{
        validation_context_type:
          {:validation_context_sds_secret_config, %Ext.SdsSecretConfig{name: secret_name}},
        alpn_protocols: Keyword.get(opts, :alpn_protocols, [])
      }
    }

    Xds.transport_socket(@tls_socket, :upstream_tls_context, context)
  end

  def downstream_sds_certificate(secret_name, opts \\ []) do
    context = %Ext.DownstreamTlsContext{
      common_tls_context: %Ext.CommonTlsContext{
        tls_certificate_sds_secret_configs: [%Ext.SdsSecretConfig{name: secret_name}],
        alpn_protocols: Keyword.get(opts, :alpn_protocols, [])
      },
      require_client_certificate: bool(Keyword.get(opts, :require_client_certificate))
    }

    Xds.transport_socket(@tls_socket, :downstream_tls_context, context)
  end

  def validation_context(trusted_ca),
    do: %Ext.CertificateValidationContext{trusted_ca: trusted_ca}

  def certificate(chain, private_key),
    do: %Ext.TlsCertificate{certificate_chain: chain, private_key: private_key}
end
