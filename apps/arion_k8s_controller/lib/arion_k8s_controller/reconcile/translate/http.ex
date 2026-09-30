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

defmodule Arion.K8sController.Reconcile.Translate.Http do
  @moduledoc """
  Builds an Envoy RouteConfiguration from attached HTTP/GRPC routes.
  """

  alias Arion.ControlPlane.Helpers.{Cors, Route, RouteConfig, VirtualHost}
  alias Arion.K8sController.Ir
  alias Arion.K8sController.Reconcile.Precedence
  alias Arion.K8sController.Reconcile.Resolve.Hostname
  alias Arion.K8sController.Reconcile.Translate.{Backend, Inference}

  @unit_ms %{"h" => 3_600_000, "m" => 60_000, "s" => 1_000, "ms" => 1}
  @default_ports %{"http" => 80, "https" => 443}
  @cors_filter_name "envoy.filters.http.cors"

  def cors_filter_name, do: @cors_filter_name

  @doc """
  One route config for a port's HTTP listeners. A domain belongs to the most
  specific listener hostname covering it, and hostnames left without a virtual
  host get a 404 one, so routes cannot serve traffic a sibling listener owns.
  """
  def http_config(config_name, group, listener) do
    build_config(config_name, group, group, listener, :not_found)
  end

  @doc """
  The route config of one HTTPS SNI chain. Hosts outside the chain's hostname
  are misdirected (421): covered by a catch-all on a hostname chain, and by
  sibling-hostname virtual hosts on the default chain.
  """
  def https_config(config_name, chain_listener, https_group, listener) do
    build_config(config_name, [chain_listener], https_group, listener, :misdirected)
  end

  defp build_config(config_name, chain_listeners, all_listeners, listener, mode) do
    inference? =
      chain_listeners
      |> Enum.flat_map(& &1.attached_routes)
      |> Enum.flat_map(&Ir.Route.backends/1)
      |> Enum.any?(&Backend.inference?/1)

    by_domain = candidates_by_domain(chain_listeners, all_listeners, inference?)

    vhosts =
      Enum.map(by_domain, fn {domain, candidates} ->
        routes = candidates |> Precedence.sort() |> Enum.map(&build_route(&1, listener))

        VirtualHost.new(vhost_name(config_name, domain), [domain])
        |> VirtualHost.put_routes(routes)
      end)

    shadows =
      shadow_vhosts(config_name, chain_listeners, all_listeners, Map.keys(by_domain), mode)

    RouteConfig.new(config_name)
    |> RouteConfig.put_virtual_hosts(or_not_found(vhosts ++ shadows, config_name))
  end

  # The proxy rejects a route config without virtual hosts.
  defp or_not_found([], config_name) do
    [direct_vhost(config_name, "*", 404)]
  end

  defp or_not_found(vhosts, _config_name), do: vhosts

  defp candidates_by_domain(chain_listeners, all_listeners, inference?) do
    for chain_listener <- chain_listeners,
        entry <- chain_listener.attached_routes,
        domain <- entry.domains,
        owner?(all_listeners, chain_listener, domain),
        rule <- entry.rules,
        match <- rule.matches do
      {domain,
       %{
         match: match,
         rule: rule,
         namespace: entry.namespace,
         name: entry.name,
         creation_ts: entry.creation_ts,
         listener_inference?: inference?
       }}
    end
    |> Enum.group_by(fn {domain, _} -> domain end, fn {_, c} -> c end)
  end

  defp owner?(all_listeners, chain_listener, domain) do
    all_listeners
    |> Enum.filter(&Hostname.covers?(&1.hostname, domain))
    |> Enum.min_by(&Hostname.rank(&1.hostname), fn -> chain_listener end)
    |> then(&(&1.hostname == chain_listener.hostname))
  end

  defp shadow_vhosts(config_name, _chain_listeners, all_listeners, domains, :not_found) do
    for %Ir.Listener{hostname: hostname} <- all_listeners,
        is_binary(hostname) and hostname not in domains,
        do: direct_vhost(config_name, hostname, 404)
  end

  defp shadow_vhosts(
         config_name,
         [%Ir.Listener{hostname: nil}],
         all_listeners,
         domains,
         :misdirected
       ) do
    for %Ir.Listener{hostname: hostname} <- all_listeners,
        is_binary(hostname) and hostname not in domains,
        do: direct_vhost(config_name, hostname, 421)
  end

  defp shadow_vhosts(config_name, [%Ir.Listener{hostname: hostname}], _all, domains, :misdirected) do
    own = if hostname in domains, do: [], else: [direct_vhost(config_name, hostname, 404)]
    own ++ [direct_vhost(config_name, "*", 421)]
  end

  defp direct_vhost(config_name, domain, status) do
    route = Route.new() |> Route.direct_response(status)
    VirtualHost.new(vhost_name(config_name, domain), [domain]) |> VirtualHost.add_route(route)
  end

  defp build_route(candidate, listener) do
    Route.new(route_name(candidate))
    |> Route.put_match(build_match(candidate.match))
    |> apply_backends(candidate.rule.backends)
    |> apply_filters(candidate.rule.filters, listener)
    |> apply_backend_filters(candidate.rule.backends)
    |> apply_timeouts_and_retry(candidate.rule)
    |> apply_ext_proc(candidate.rule.backends, candidate.listener_inference?)
  end

  defp apply_ext_proc(route, _backends, false), do: route

  defp apply_ext_proc(route, backends, true) do
    case Enum.find(backends, &Backend.inference?/1) do
      nil -> Inference.per_route_disable(route)
      backend -> Inference.per_route_enable(route, backend)
    end
  end

  defp build_match(match) do
    match
    |> path_match()
    |> add_headers(match["headers"])
    |> add_queries(match["queryParams"])
    |> add_method(match["method"])
  end

  defp path_match(%{"path" => %{"type" => "Exact", "value" => v}}), do: Route.match_path(v)

  defp path_match(%{"path" => %{"type" => "RegularExpression", "value" => v}}),
    do: Route.match_regex(v)

  defp path_match(%{"path" => %{"type" => "PathPrefix", "value" => "/"}}),
    do: Route.match_prefix("/")

  # A trailing slash is insignificant, and the proxy rejects one here.
  defp path_match(%{"path" => %{"type" => "PathPrefix", "value" => v}}),
    do: Route.match_path_separated_prefix(String.trim_trailing(v, "/"))

  defp path_match(_), do: Route.match_prefix("/")

  defp add_headers(match, nil), do: match

  defp add_headers(match, headers) do
    Enum.reduce(headers, match, fn h, acc -> Route.add_header(acc, header_matcher(h)) end)
  end

  defp header_matcher(%{"type" => "RegularExpression", "name" => n, "value" => v}),
    do: Route.header_match(:regex, n, v)

  defp header_matcher(%{"name" => n, "value" => v}), do: Route.header_match(:exact, n, v)

  defp add_queries(match, nil), do: match

  defp add_queries(match, queries) do
    Enum.reduce(queries, match, fn q, acc -> Route.add_query(acc, query_matcher(q)) end)
  end

  defp query_matcher(%{"type" => "RegularExpression", "name" => n, "value" => v}),
    do: Route.query_match(n, Route.string_matcher(:regex, v))

  defp query_matcher(%{"name" => n, "value" => v}),
    do: Route.query_match(n, Route.string_matcher(:exact, v))

  defp add_method(match, nil), do: match

  defp add_method(match, method),
    do: Route.add_header(match, Route.header_match(:exact, ":method", method))

  defp apply_backends(route, backends) do
    case Backend.weighted_clusters(backends) do
      [] ->
        Route.direct_response(route, 500)

      [{cluster, _weight}] ->
        Route.to_cluster(route, cluster)

      weighted ->
        route = Route.to_weighted_clusters(route, weighted)

        if List.keymember?(weighted, Backend.invalid_cluster(), 0),
          do: Route.cluster_not_found_response_code(route, :INTERNAL_SERVER_ERROR),
          else: route
    end
  end

  # One branch per validated filter type (see `Ir.Rule`); there is no catch-all.
  defp apply_filters(route, filters, listener) do
    Enum.reduce(filters, route, &apply_filter(&1, &2, listener))
  end

  defp apply_filter({:request_header_modifier, mod}, route, _listener),
    do: header_mods(route, mod, :request)

  defp apply_filter({:response_header_modifier, mod}, route, _listener),
    do: header_mods(route, mod, :response)

  defp apply_filter({:request_redirect, redirect}, route, listener),
    do: Route.redirect(route, redirect_opts(redirect, listener))

  # Only a forwarding action has an upstream request to rewrite.
  defp apply_filter({:url_rewrite, rewrite}, %{action: {:route, _}} = route, _listener),
    do: apply_path_rewrite(route, rewrite["path"])

  defp apply_filter({:url_rewrite, _rewrite}, route, _listener), do: route

  defp apply_filter({:cors, cors}, route, _listener),
    do: Cors.per_route(route, @cors_filter_name, cors_policy(cors))

  defp cors_policy(cors) do
    %Arion.ControlPlane.Pb.Data.Extensions.CorsPolicy{
      allow_origin_string_match: Enum.map(cors["allowOrigins"] || [], &origin_matcher/1),
      allow_methods: Enum.join(cors["allowMethods"] || [], ","),
      allow_headers: Enum.join(cors["allowHeaders"] || [], ","),
      expose_headers: Enum.join(cors["exposeHeaders"] || [], ","),
      max_age: to_string(cors["maxAge"] || 5),
      allow_credentials: cors_credentials(cors["allowCredentials"]),
      # The Gateway answers preflights from other origins itself, as the Gateway API expects.
      forward_not_matching_preflights: %Google.Protobuf.BoolValue{value: false}
    }
  end

  # The proxy grants "*" responses for a matcher that matches the literal "*".
  defp origin_matcher("*"), do: Route.string_matcher(:exact, "*")

  defp origin_matcher(origin) do
    if String.contains?(origin, "*") do
      Route.string_matcher(:regex, origin |> Regex.escape() |> String.replace("\\*", ".*"))
    else
      Route.string_matcher(:exact, origin)
    end
  end

  defp cors_credentials(true), do: %Google.Protobuf.BoolValue{value: true}
  defp cors_credentials(_false_or_nil), do: nil

  defp apply_backend_filters(%{action: {:route, _}} = route, backends) do
    case Enum.filter(backends, &(&1.weight > 0)) do
      [%{resolved?: true, filters: [_ | _] = filters}] -> fold_header_filters(route, filters)
      _zero_or_many -> route
    end
  end

  defp apply_backend_filters(route, _backends), do: route

  defp fold_header_filters(route, filters) do
    Enum.reduce(filters, route, fn
      {:request_header_modifier, mod}, acc -> header_mods(acc, mod, :request)
      {:response_header_modifier, mod}, acc -> header_mods(acc, mod, :response)
    end)
  end

  # Arion builds Location from the request URI, which on HTTP/1.1 has no scheme or
  # authority: a hostname needs an explicit scheme, and without either Location
  # stays relative, keeping the client's scheme, host and port.
  defp redirect_opts(redirect, {scheme, port}) do
    [
      scheme: redirect_scheme(redirect, scheme),
      response_code: redirect_code(redirect["statusCode"])
    ]
    |> put_opt(:host, redirect["hostname"])
    |> put_opt(:port, redirect["port"] || listener_port(redirect, scheme, port))
    |> put_path_opt(redirect["path"])
  end

  # An empty scheme is the request's, i.e. the listener's; false disables the
  # helper's https default.
  defp redirect_scheme(%{"scheme" => s}, _listener_scheme) when is_binary(s), do: s
  defp redirect_scheme(%{"hostname" => h}, listener_scheme) when is_binary(h), do: listener_scheme
  defp redirect_scheme(_redirect, _listener_scheme), do: false

  # With an empty scheme the port MUST be the listener's; a default one is left out.
  defp listener_port(redirect, scheme, port) do
    if redirect["hostname"] && is_nil(redirect["scheme"]) && port != @default_ports[scheme],
      do: port
  end

  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp put_path_opt(opts, nil), do: opts

  defp put_path_opt(opts, %{"type" => "ReplaceFullPath", "replaceFullPath" => p}),
    do: Keyword.put(opts, :path_redirect, p)

  defp put_path_opt(opts, %{"type" => "ReplacePrefixMatch", "replacePrefixMatch" => p}),
    do: Keyword.put(opts, :prefix_rewrite, p)

  # The v1.6.0 CRD allows 301, 302, 303, 307 and 308 and defaults to 302.
  defp redirect_code(301), do: :MOVED_PERMANENTLY
  defp redirect_code(303), do: :SEE_OTHER
  defp redirect_code(307), do: :TEMPORARY_REDIRECT
  defp redirect_code(308), do: :PERMANENT_REDIRECT
  defp redirect_code(_302_or_nil), do: :FOUND

  defp apply_path_rewrite(route, nil), do: route

  defp apply_path_rewrite(route, %{"type" => "ReplacePrefixMatch", "replacePrefixMatch" => p}),
    do: Route.prefix_rewrite(route, p)

  defp apply_path_rewrite(route, %{"type" => "ReplaceFullPath", "replaceFullPath" => p}),
    do: Route.regex_rewrite(route, "^.*$", p)

  defp header_mods(route, mod, direction) do
    route
    |> add_header_ops(mod["set"], :overwrite_if_exists_or_add, direction)
    |> add_header_ops(mod["add"], :append_if_exists_or_add, direction)
    |> remove_headers(mod["remove"], direction)
  end

  defp add_header_ops(route, nil, _action, _direction), do: route

  defp add_header_ops(route, headers, action, direction) do
    Enum.reduce(headers, route, fn %{"name" => n, "value" => v}, acc ->
      update = Route.header_update(action, Route.header_value(n, v))

      case direction do
        :request -> Route.add_request_header(acc, update)
        :response -> Route.add_response_header(acc, update)
      end
    end)
  end

  defp remove_headers(route, nil, _direction), do: route

  defp remove_headers(route, names, direction) do
    Enum.reduce(names, route, fn name, acc ->
      case direction do
        :request -> Route.remove_request_header(acc, name)
        :response -> Route.remove_response_header(acc, name)
      end
    end)
  end

  defp apply_timeouts_and_retry(%{action: {:route, _}} = route, rule) do
    request = parse_duration_ms(rule.timeouts["request"])
    backend_request = nonzero_ms(rule.timeouts["backendRequest"])

    route
    |> put_timeout(route_timeout(request, backend_request, rule.retry))
    |> apply_retry(rule.retry, backend_request)
  end

  defp apply_timeouts_and_retry(route, _rule), do: route

  # Without a retry stanza one backend request is the whole transaction.
  defp route_timeout(request, backend_request, nil)
       when is_integer(backend_request) and (request in [nil, 0] or request > backend_request),
       do: backend_request

  defp route_timeout(request, _backend_request, _retry), do: request

  defp put_timeout(route, nil), do: route
  defp put_timeout(route, ms), do: Route.timeout(route, duration(ms))

  defp apply_retry(route, nil, _per_try_ms), do: route

  defp apply_retry(route, retry, per_try_ms) do
    opts =
      [
        retriable_status_codes: retry["codes"] || [],
        per_try_timeout: duration(per_try_ms),
        max_interval: nil
      ]
      |> put_opt(:num_retries, retry["attempts"])
      |> put_opt(:base_interval, duration(nonzero_ms(retry["backoff"])))

    Route.retry(route, Route.retry_policy("retriable-status-codes", opts))
  end

  defp nonzero_ms(dur) do
    case parse_duration_ms(dur) do
      0 -> nil
      ms -> ms
    end
  end

  def parse_duration_ms(dur) when is_binary(dur) do
    if dur =~ ~r/^([0-9]{1,5}(h|m|s|ms)){1,4}$/ do
      ~r/(\d+)(ms|h|m|s)/
      |> Regex.scan(dur, capture: :all_but_first)
      |> Enum.sum_by(fn [n, unit] -> String.to_integer(n) * @unit_ms[unit] end)
    end
  end

  def parse_duration_ms(_dur), do: nil

  defp duration(nil), do: nil

  defp duration(ms),
    do: %Google.Protobuf.Duration{seconds: div(ms, 1000), nanos: rem(ms, 1000) * 1_000_000}

  defp vhost_name(config_name, domain), do: "#{config_name}/#{domain}"
  defp route_name(%{namespace: ns, name: name}), do: "#{ns}/#{name}"
end
