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

defmodule Arion.K8sController.Ir do
  @moduledoc """
  Resolved Gateway API graph shared by translation, status, and provisioning.

  Keeping these plain structs separate from raw Kubernetes objects and Arion xDS
  structs keeps the reconcile pipeline pure.
  """

  defmodule GatewayClass do
    @moduledoc """
    A claimed GatewayClass.

    `params` is the spec of the ArionGatewayParameters its parametersRef names,
    `%{}` without one. `invalid_params` is nil or why that reference cannot be
    used; the Gateways of such a class are not accepted, translated or
    provisioned.
    """
    defstruct [:name, :controller_name, :generation, :invalid_params, params: %{}]
  end

  defmodule Tls do
    @moduledoc "Resolved listener TLS config."
    defstruct certificates: []
  end

  defmodule Attachment do
    @moduledoc """
    A route as one listener accepted it: the `domains` their hostnames
    intersect to, and the route's rules. Routes on a listener are ordered as
    they were attached, oldest first.
    """
    defstruct [:namespace, :name, :creation_ts, domains: [], rules: []]
  end

  defmodule Listener do
    @moduledoc """
    A resolved Gateway listener.

    `conflict` is nil or the reason the listener cannot share its port,
    `overlapping_tls?` marks an HTTPS hostname overlapping another on the port,
    and `resolved_reason` is its ResolvedRefs reason. `attached_routes` are the
    `Attachment`s of the routes it accepted. Only `programmed?/1` listeners are
    translated.
    """
    defstruct [
      :name,
      :port,
      :protocol,
      :hostname,
      :tls,
      conflict: nil,
      overlapping_tls?: false,
      resolved_reason: "ResolvedRefs",
      allowed_routes: %{namespaces: :same, kinds: []},
      attached_routes: []
    ]

    @supported_protocols [:http, :https, :tcp, :tls_passthrough, :tls_terminate]
    @terminating [:https, :tls_terminate]

    def supported?(%__MODULE__{protocol: protocol}), do: protocol in @supported_protocols

    def accepted?(%__MODULE__{} = listener),
      do: supported?(listener) and is_nil(listener.conflict)

    # A terminating listener serves its first usable certificate.
    def programmed?(%__MODULE__{protocol: protocol, tls: %Tls{certificates: [_ | _]}} = listener)
        when protocol in @terminating,
        do: accepted?(listener)

    def programmed?(%__MODULE__{protocol: protocol}) when protocol in @terminating, do: false
    def programmed?(%__MODULE__{} = listener), do: accepted?(listener)
  end

  defmodule Gateway do
    @moduledoc """
    A resolved Gateway.

    `params` is its effective ArionGatewayParameters spec: the whole spec its
    own parametersRef names, else its class's, else `%{}`; provisioning fills
    the rest from controller defaults. `invalid_params` is nil or why its
    parametersRef cannot be used; such a Gateway is not accepted, translated or
    provisioned.
    """
    defstruct [
      :namespace,
      :name,
      :uid,
      :generation,
      :class_name,
      :invalid_params,
      params: %{},
      infrastructure: %{},
      programmed?: false,
      listeners: [],
      addresses: []
    ]

    # The fleet (the data plane's node.cluster): unambiguous, as Kubernetes names have no '/'.
    def fleet(%__MODULE__{namespace: ns, name: name}), do: fleet(ns, name)
    def fleet(ns, name), do: "gateway/#{ns}/#{name}"

    @doc "Whether a fleet name is one of this controller's Gateway fleets."
    def fleet?(fleet), do: String.starts_with?(fleet, "gateway/")

    # The provisioned data plane's objects, in the Gateway's namespace.
    def object_name(%__MODULE__{namespace: ns, name: name}), do: object_name(ns, name)

    # A name that sanitizing changed keeps a hash, as 'a.b' and 'a-b' both become 'a-b'.
    def object_name(ns, name) do
      plain = "gateway-#{ns}-#{name}"
      sanitized = plain |> String.downcase() |> String.replace(~r/[^a-z0-9-]/, "-")
      key = "#{ns}/#{name}"
      if sanitized == plain, do: fit(plain, key), else: hashed(sanitized, key)
    end

    def name_label(%__MODULE__{name: name}), do: fit(name, name)

    # Kubernetes names and label values have at most 63 characters: a longer one
    # keeps its start and a hash of what it derives from.
    defp fit(value, _key) when byte_size(value) <= 63, do: value
    defp fit(value, key), do: hashed(value, key)

    defp hashed(value, key) do
      hash = :sha256 |> :crypto.hash(key) |> Base.encode16(case: :lower)
      binary_slice(value, 0, 52) <> "-" <> binary_part(hash, 0, 10)
    end
  end

  defmodule Backend do
    @moduledoc """
    A resolved `backendRef`; unresolved backends feed `ResolvedRefs` status and
    have no cluster.

    `protocol` is the effective upstream protocol, `:http1` or `:http2`, derived
    from the route kind and the selected port's appProtocol; it is part of the
    `cluster_name`, so one Service port serves each protocol from its own
    cluster. `endpoints` are the ready `{address, port}` pairs of a Service
    backend, or of an InferencePool's selected pods on each of its target ports.
    `filters` are the backendRef's validated header filters, as in `Rule`.
    """
    defstruct [
      :namespace,
      :name,
      :port,
      :cluster_name,
      weight: 1,
      endpoints: [],
      filters: [],
      protocol: :http1,
      inference?: false,
      epp: nil,
      resolved?: true,
      reason: nil
    ]
  end

  defmodule Rule do
    @moduledoc """
    One resolved route rule.

    `filters` are validated once into `{type, config}` values, in order, with
    the Gateway API object of that filter as `config`: `:request_header_modifier`
    and `:response_header_modifier` (`"set"`, `"add"`, `"remove"`),
    `:request_redirect`, `:url_rewrite` (path only) and `:cors`. Translation
    has a branch for each; a filter that cannot be validated makes its route
    `unsupported` instead.
    """
    defstruct matches: [], filters: [], backends: [], timeouts: %{}, retry: nil
  end

  defmodule Parent do
    @moduledoc """
    A route's or InferencePool's status on one of this controller's Gateways:
    whether it attached and whether its references resolved, with the Gateway
    API reasons.
    """
    defstruct [
      :parent_ref,
      :controller_name,
      accepted?: true,
      accepted_reason: "Accepted",
      resolved_refs?: true,
      resolved_reason: "ResolvedRefs"
    ]
  end

  defmodule Route do
    @moduledoc """
    A resolved route (HTTP/GRPC/TLS/TCP/UDP).

    `unsupported` is nil or why the data plane cannot serve the route, which
    then attaches nowhere. `parents` are its `Parent`s on Arion Gateways;
    `other_parents` are the live status entries of other controllers, written
    back unchanged beside them.
    """
    defstruct [
      :namespace,
      :name,
      :kind,
      :generation,
      :creation_ts,
      :unsupported,
      hostnames: [],
      rules: [],
      parent_refs: [],
      parents: [],
      other_parents: []
    ]

    @doc "The backends of every rule of a route, or of a listener's attachment."
    def backends(%{rules: rules}), do: Enum.flat_map(rules, & &1.backends)
  end

  defmodule ReferenceGrant do
    @moduledoc "A resolved ReferenceGrant in a target namespace."
    defstruct [:namespace, froms: [], tos: []]
  end

  defmodule InferencePool do
    @moduledoc """
    A resolved Gateway API Inference Extension InferencePool.

    `parents` are its `Parent`s on the Gateways of the routes using it;
    `other_parents` are the live status entries of other controllers, written
    back unchanged beside them.
    """
    defstruct [:namespace, :name, :generation, parents: [], other_parents: []]
  end

  defmodule Graph do
    @moduledoc "The resolved world for one recompute."
    defstruct classes: [], gateways: [], routes: [], inference_pools: []
  end
end
