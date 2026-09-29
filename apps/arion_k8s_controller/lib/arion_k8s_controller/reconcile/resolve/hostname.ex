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

defmodule Arion.K8sController.Reconcile.Resolve.Hostname do
  @moduledoc """
  Gateway API hostname policy, shared by route attachment and by the listener
  and HTTP translations.

  A hostname is an exact name or a `*.` wildcard covering the names under its
  suffix, not the suffix itself. A listener without a hostname, nil, covers
  every name.
  """

  @doc "Whether `host` covers `domain`; only a listener without a hostname covers every name."
  def covers?(nil, _domain), do: true
  def covers?(_host, nil), do: false
  def covers?(host, host), do: true
  def covers?("*." <> suffix, domain), do: String.ends_with?(domain, "." <> suffix)
  def covers?(_host, _domain), do: false

  @doc "Whether two hostnames share a name: one covers the other."
  def overlap?(a, b), do: covers?(a, b) or covers?(b, a)

  @doc "The narrower of two hostnames when one covers the other, else nil."
  def narrower(a, b) do
    cond do
      covers?(a, b) -> b
      covers?(b, a) -> a
      true -> nil
    end
  end

  @doc """
  The domains a listener hostname and a route's hostnames both cover, the
  narrower of each pair, or `:none`. A route without hostnames takes the
  listener's, and `"*"` on a listener without one.
  """
  def intersect(listener_host, []), do: [listener_host || "*"]
  def intersect(nil, route_hosts), do: route_hosts

  def intersect(listener_host, route_hosts) do
    case for(host <- route_hosts, domain = narrower(listener_host, host), uniq: true, do: domain) do
      [] -> :none
      domains -> domains
    end
  end

  @doc "Sort key from most to least specific: exact names, wildcards with more labels, then none."
  def rank(nil), do: {2, 0}
  def rank("*." <> _ = host), do: {1, -length(String.split(host, "."))}
  def rank(_host), do: {0, 0}
end
