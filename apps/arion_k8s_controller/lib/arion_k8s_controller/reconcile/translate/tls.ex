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

defmodule Arion.K8sController.Reconcile.Translate.Tls do
  @moduledoc """
  Builds SDS secrets and downstream TLS sockets for HTTPS and TLS termination.

  A terminating listener serves its first certificate, so only that one is shipped.
  """

  alias Arion.ControlPlane.Helpers.{Secret, Tls}
  alias Arion.K8sController.Ir

  def secrets(listeners) do
    listeners
    |> Enum.flat_map(&certificates/1)
    |> Enum.uniq_by(& &1.sds_name)
    |> Enum.map(&secret_resource/1)
  end

  # No alpn_protocols: the proxy rejects them and negotiates h2 or http/1.1 from
  # the HCM codec type.
  def transport_socket(%Ir.Listener{tls: %Ir.Tls{certificates: [cert | _]}}) do
    Tls.downstream_sds_certificate(cert.sds_name)
  end

  def transport_socket(_listener), do: nil

  defp certificates(%Ir.Listener{tls: %Ir.Tls{certificates: [cert | _]}}), do: [cert]
  defp certificates(_listener), do: []

  defp secret_resource(cert) do
    certificate =
      Tls.certificate(
        Secret.data_source(:inline_bytes, cert.cert_pem),
        Secret.data_source(:inline_bytes, cert.key_pem)
      )

    Secret.tls_certificate(cert.sds_name, certificate)
  end
end
