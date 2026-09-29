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

defmodule Arion.K8sController.Reconcile.Resolve.Reference do
  @moduledoc """
  ReferenceGrant policy: whether a Gateway or route may refer to an object in
  another namespace.

  A cross-namespace reference needs a grant in the referent's namespace that
  trusts the referrer (`{kind, namespace}`; the group is always
  gateway.networking.k8s.io) for the referent's group, kind and, when the grant
  names one, name.
  """

  alias Arion.K8sController.Ir
  alias Arion.K8sController.Kube.Gvk

  def parse_grant(obj) do
    %Ir.ReferenceGrant{
      namespace: get_in(obj, ["metadata", "namespace"]),
      froms: get_in(obj, ["spec", "from"]) || [],
      tos: get_in(obj, ["spec", "to"]) || []
    }
  end

  @doc """
  Checks a reference to the `{group, kind, namespace, name}` referent, which
  `index` must hold under `{namespace, name}`: `:ok`, or the reason, a grant
  first and then `missing`.
  """
  def check(grants, from, {_group, _kind, ns, name} = referent, index, missing) do
    cond do
      not permitted?(grants, from, referent) -> {:error, :ref_not_permitted}
      not Map.has_key?(index, {ns, name}) -> {:error, missing}
      true -> :ok
    end
  end

  def permitted?(_grants, {_from_kind, ns}, {_group, _kind, ns, _name}), do: true

  def permitted?(grants, {from_kind, from_ns}, {group, kind, ns, name}) do
    Enum.any?(grants, fn grant ->
      grant.namespace == ns and
        Enum.any?(grant.froms, fn f ->
          f["group"] == Gvk.gateway_group() and f["kind"] == from_kind and
            f["namespace"] == from_ns
        end) and
        Enum.any?(grant.tos, fn t ->
          (t["group"] || "") == group and t["kind"] == kind and t["name"] in [nil, name]
        end)
    end)
  end
end
