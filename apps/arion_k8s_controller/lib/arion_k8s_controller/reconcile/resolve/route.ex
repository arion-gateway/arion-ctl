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

defmodule Arion.K8sController.Reconcile.Resolve.Route do
  @moduledoc """
  Parses HTTP, GRPC, TLS, TCP and UDP routes: their rules, matches, filters
  and backendRefs.

  Filters are validated once into the `{type, config}` values `Ir.Rule`
  documents. A route with a filter the data plane cannot apply, or with
  backend filters on a rule splitting traffic between backends, is marked
  `unsupported` and attaches nowhere; its rules are still parsed.
  """

  alias Arion.K8sController.Ir
  alias Arion.K8sController.Reconcile.Resolve.Backend

  # Gateway API filter type => {tag, the key holding its configuration}.
  @filters %{
    "RequestHeaderModifier" => {:request_header_modifier, "requestHeaderModifier"},
    "ResponseHeaderModifier" => {:response_header_modifier, "responseHeaderModifier"},
    "RequestRedirect" => {:request_redirect, "requestRedirect"},
    "URLRewrite" => {:url_rewrite, "urlRewrite"},
    "CORS" => {:cors, "cors"}
  }
  @backend_filters Map.take(@filters, ["RequestHeaderModifier", "ResponseHeaderModifier"])

  def parse(kind, obj, ctx) do
    ns = get_in(obj, ["metadata", "namespace"])
    rules = get_in(obj, ["spec", "rules"]) || []

    %Ir.Route{
      namespace: ns,
      name: get_in(obj, ["metadata", "name"]),
      kind: kind,
      generation: get_in(obj, ["metadata", "generation"]) || 0,
      creation_ts: get_in(obj, ["metadata", "creationTimestamp"]),
      hostnames: get_in(obj, ["spec", "hostnames"]) || [],
      parent_refs: get_in(obj, ["spec", "parentRefs"]) || [],
      other_parents: other_parents(obj, ctx.controller_name),
      unsupported: unsupported(rules),
      rules: Enum.map(rules, &parse_rule(kind, &1, ns, ctx))
    }
  end

  @doc "The live status parents of other controllers, written back beside ours."
  def other_parents(obj, controller_name) do
    Enum.reject(get_in(obj, ["status", "parents"]) || [], fn parent ->
      parent["controllerName"] == controller_name
    end)
  end

  defp parse_rule(kind, rule, route_ns, ctx) do
    %Ir.Rule{
      matches: rule_matches(kind, rule["matches"]),
      filters: filters(rule["filters"], @filters),
      timeouts: rule["timeouts"] || %{},
      retry: rule["retry"],
      backends:
        for ref <- rule["backendRefs"] || [] do
          %{
            Backend.resolve(kind, ref, route_ns, ctx)
            | filters: filters(ref["filters"], @backend_filters)
          }
        end
    }
  end

  defp rule_matches(:http, nil), do: [%{"path" => %{"type" => "PathPrefix", "value" => "/"}}]
  defp rule_matches(:http, matches), do: matches
  defp rule_matches(:grpc, nil), do: [grpc_match(%{})]
  defp rule_matches(:grpc, matches), do: Enum.map(matches, &grpc_match/1)
  defp rule_matches(_l4, _matches), do: []

  # "grpc" keeps the method match for GRPCRoute precedence.
  defp grpc_match(match) do
    method = match["method"] || %{}
    path = grpc_path(method["type"], method["service"], method["method"])
    %{"path" => path, "headers" => match["headers"], "grpc" => method}
  end

  defp grpc_path("RegularExpression", service, method),
    do: %{"type" => "RegularExpression", "value" => "/#{service || "[^/]+"}/#{method || "[^/]+"}"}

  defp grpc_path(_exact, service, method) when is_binary(service) and is_binary(method),
    do: %{"type" => "Exact", "value" => "/#{service}/#{method}"}

  defp grpc_path(_exact, service, nil) when is_binary(service),
    do: %{"type" => "PathPrefix", "value" => "/#{service}/"}

  defp grpc_path(_exact, nil, method) when is_binary(method),
    do: %{"type" => "RegularExpression", "value" => "/[^/]+/#{method}"}

  defp grpc_path(_exact, _service, _method), do: %{"type" => "PathPrefix", "value" => "/"}

  # Invalid filters already made the route unsupported.
  defp filters(filters, allowed),
    do: for({:ok, filter} <- Enum.map(List.wrap(filters), &parse_filter(&1, allowed)), do: filter)

  defp unsupported(rules) do
    Enum.find_value(rules, fn rule ->
      filter_error(rule["filters"], @filters) || backend_filter_error(rule)
    end)
  end

  defp filter_error(filters, allowed) do
    Enum.find_value(List.wrap(filters), fn filter ->
      case parse_filter(filter, allowed) do
        {:error, reason} -> reason
        {:ok, _filter} -> nil
      end
    end)
  end

  # Backend filters fold into the route only when one backend carries traffic.
  defp backend_filter_error(rule) do
    refs = rule["backendRefs"] || []
    with_filters = Enum.filter(refs, &(List.wrap(&1["filters"]) != []))

    cond do
      with_filters == [] ->
        nil

      error = Enum.find_value(with_filters, &filter_error(&1["filters"], @backend_filters)) ->
        error

      Enum.count(refs, &(Map.get(&1, "weight", 1) > 0)) > 1 ->
        "backend filters on a rule with several weighted backends"

      true ->
        nil
    end
  end

  defp parse_filter(%{"type" => type} = filter, allowed) do
    case Map.fetch(allowed, type) do
      {:ok, {tag, key}} -> check_filter(tag, type, filter[key])
      :error -> {:error, "unsupported filter #{type}"}
    end
  end

  defp parse_filter(_filter, _allowed), do: {:error, "filter without a type"}

  # A hostname rewrite is a proto gap.
  defp check_filter(:url_rewrite, _type, %{"hostname" => host}) when is_binary(host),
    do: {:error, "URLRewrite hostname is not supported"}

  defp check_filter(tag, type, %{} = config) when tag in [:url_rewrite, :request_redirect] do
    if path?(config["path"]),
      do: {:ok, {tag, config}},
      else: {:error, "#{type} path is malformed"}
  end

  defp check_filter(tag, _type, %{} = config), do: {:ok, {tag, config}}
  defp check_filter(_tag, type, _config), do: {:error, "#{type} filter without its configuration"}

  defp path?(nil), do: true
  defp path?(%{"type" => "ReplaceFullPath", "replaceFullPath" => path}), do: is_binary(path)
  defp path?(%{"type" => "ReplacePrefixMatch", "replacePrefixMatch" => path}), do: is_binary(path)
  defp path?(_path), do: false
end
