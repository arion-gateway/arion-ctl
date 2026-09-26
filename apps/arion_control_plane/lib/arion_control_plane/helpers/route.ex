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

defmodule Arion.ControlPlane.Helpers.Route do
  @moduledoc """
  Routes: what a request must match and where it goes.

  `new/1` starts a route matching every path with no action. Destination
  helpers (`to_cluster/2` and friends) set where it forwards; the refinements
  below adjust that forwarding action and require one to exist. `add_*`
  accumulates in call order, `put_*` replaces a whole value. Durations are
  seconds unless a `Google.Protobuf.Duration` is given; `nil` leaves a wrapper
  field unset.
  """

  import Arion.ControlPlane.Helpers.Xds, only: [duration: 1, bool: 1, uint32: 1]

  alias Arion.ControlPlane.Helpers.Xds
  alias Arion.ControlPlane.Pb
  alias Arion.ControlPlane.Pb.Route.{Route, RouteAction, RouteMatch}

  @type route :: Route.t()
  @type match :: RouteMatch.t()
  @type seconds :: non_neg_integer() | Google.Protobuf.Duration.t() | nil

  @append_actions %{
    append_if_exists_or_add: :APPEND_IF_EXISTS_OR_ADD,
    add_if_not_exists: :ADD_IF_ABSENT,
    overwrite_if_exists_or_add: :OVERWRITE_IF_EXISTS_OR_ADD,
    overwrite_if_exists: :OVERWRITE_IF_EXISTS
  }

  @doc "A route matching the `/` prefix, case sensitively, with no action yet."
  @spec new(String.t()) :: route
  def new(name \\ ""), do: %Route{name: name, match: match_prefix("/")}

  @spec match_prefix(String.t()) :: match
  def match_prefix(prefix), do: match({:prefix, prefix})

  @spec match_path(String.t()) :: match
  def match_path(path), do: match({:path, path})

  @spec match_path_separated_prefix(String.t()) :: match
  def match_path_separated_prefix(prefix), do: match({:path_separated_prefix, prefix})

  @spec match_regex(String.t()) :: match
  def match_regex(regex), do: match({:safe_regex, regex_matcher(regex)})

  @doc "Replaces the route's whole match."
  @spec put_match(route, match) :: route
  def put_match(%Route{} = route, %RouteMatch{} = match), do: %{route | match: match}

  # Path refinements: change only the path of the route's match, keeping its
  # headers, query parameters and case sensitivity.
  @spec match_prefix(route, String.t()) :: route
  def match_prefix(%Route{} = route, prefix), do: put_path(route, {:prefix, prefix})

  @spec match_path(route, String.t()) :: route
  def match_path(%Route{} = route, path), do: put_path(route, {:path, path})

  @spec match_path_separated_prefix(route, String.t()) :: route
  def match_path_separated_prefix(%Route{} = route, prefix),
    do: put_path(route, {:path_separated_prefix, prefix})

  @spec match_regex(route, String.t()) :: route
  def match_regex(%Route{} = route, regex),
    do: put_path(route, {:safe_regex, regex_matcher(regex)})

  @doc "Adds a header predicate to a match; all predicates must hold."
  @spec add_header(match, Pb.Data.HeaderMatcher.t()) :: match
  def add_header(%RouteMatch{headers: headers} = match, header_matcher),
    do: %{match | headers: headers ++ [header_matcher]}

  @doc "Adds a query parameter predicate to a match; all predicates must hold."
  @spec add_query(match, Pb.Route.QueryParameterMatcher.t()) :: match
  def add_query(%RouteMatch{query_parameters: queries} = match, query_matcher),
    do: %{match | query_parameters: queries ++ [query_matcher]}

  # Destinations: change only the destination of a forwarding action; a route with
  # no action, a redirect or a direct response gets the `route_action/1` defaults.
  @spec to_cluster(route, String.t()) :: route
  def to_cluster(%Route{} = route, cluster_name),
    do: put_destination(route, {:cluster, cluster_name})

  @spec to_cluster_header(route, String.t()) :: route
  def to_cluster_header(%Route{} = route, header_name),
    do: put_destination(route, {:cluster_header, header_name})

  @doc "Forwards by weight; see `weighted_clusters/1` for the accepted distribution."
  @spec to_weighted_clusters(route, [String.t() | {String.t(), non_neg_integer()}]) :: route
  def to_weighted_clusters(%Route{} = route, clusters),
    do: put_destination(route, {:weighted_clusters, weighted_clusters(clusters)})

  @doc "A forwarding action to `{:cluster, name}` and the like, with a 15 second timeout."
  @spec route_action({atom(), term()}) :: RouteAction.t()
  def route_action({specifier, value}),
    do: %RouteAction{cluster_specifier: {specifier, value}, timeout: duration(15)}

  @doc "Replaces the route's whole action with a forwarding action."
  @spec put_action(route, RouteAction.t()) :: route
  def put_action(%Route{} = route, %RouteAction{} = action),
    do: %{route | action: {:route, action}}

  @doc "Replaces the action with a redirect; see `redirect_action/1` for the options."
  @spec redirect(route, keyword()) :: route
  def redirect(%Route{} = route, opts \\ []),
    do: %{route | action: {:redirect, redirect_action(opts)}}

  @doc "Replaces the action with a fixed response, `body` being a data source or nil."
  @spec direct_response(route, non_neg_integer(), Pb.Data.DataSource.t() | nil) :: route
  def direct_response(%Route{} = route, status, body \\ nil),
    do: %{route | action: {:direct_response, direct_response_action(status, body)}}

  @doc "The whole-request timeout; 0 disables it."
  @spec timeout(route, seconds) :: route
  def timeout(%Route{} = route, seconds),
    do: update_route_action(route, &%{&1 | timeout: duration(seconds)})

  @spec priority(route, :DEFAULT | :HIGH) :: route
  def priority(%Route{} = route, priority) when priority in [:DEFAULT, :HIGH],
    do: update_route_action(route, &%{&1 | priority: priority})

  @spec cluster_not_found_response_code(route, atom()) :: route
  def cluster_not_found_response_code(%Route{} = route, code),
    do: update_route_action(route, &%{&1 | cluster_not_found_response_code: code})

  @spec prefix_rewrite(route, String.t()) :: route
  def prefix_rewrite(%Route{} = route, prefix),
    do: update_route_action(route, &%{&1 | prefix_rewrite: prefix})

  @spec regex_rewrite(route, String.t(), String.t()) :: route
  def regex_rewrite(%Route{} = route, pattern, substitution),
    do:
      update_route_action(
        route,
        &%{&1 | regex_rewrite: regex_substitution(pattern, substitution)}
      )

  @doc "Replaces the retry policy; see `retry_policy/2`."
  @spec retry(route, Pb.Route.RetryPolicy.t() | nil) :: route
  def retry(%Route{} = route, retry_policy),
    do: update_route_action(route, &%{&1 | retry_policy: retry_policy})

  @doc "Adds a websocket upgrade config; call once per route."
  @spec websocket(route, boolean()) :: route
  def websocket(%Route{} = route, enabled \\ true) do
    upgrade = %Pb.Route.UpgradeConfig{upgrade_type: "websocket", enabled: bool(enabled)}
    update_route_action(route, &%{&1 | upgrade_configs: &1.upgrade_configs ++ [upgrade]})
  end

  # Hash policies accumulate in call order; `terminal: true` stops at that one.
  @spec hash_header(route, String.t(), keyword()) :: route
  def hash_header(%Route{} = route, header_name, opts \\ []),
    do: hash_policy(route, {:header, %Pb.Route.HashPolicy.Header{header_name: header_name}}, opts)

  @spec hash_query_parameter(route, String.t(), keyword()) :: route
  def hash_query_parameter(%Route{} = route, name, opts \\ []),
    do:
      hash_policy(
        route,
        {:query_parameter, %Pb.Route.HashPolicy.QueryParameter{name: name}},
        opts
      )

  @spec hash_source_ip(route, keyword()) :: route
  def hash_source_ip(%Route{} = route, opts \\ []),
    do:
      hash_policy(
        route,
        {:connection_properties, %Pb.Route.HashPolicy.ConnectionProperties{source_ip: true}},
        opts
      )

  @spec hash_policy(route, {atom(), struct()}, keyword()) :: route
  def hash_policy(%Route{} = route, policy_specifier, opts) do
    hash = %Pb.Route.HashPolicy{
      policy_specifier: policy_specifier,
      terminal: Keyword.get(opts, :terminal, false)
    }

    update_route_action(route, &%{&1 | hash_policy: &1.hash_policy ++ [hash]})
  end

  @doc "Sets the per-route config of the named filter, replacing an earlier one for that filter."
  @spec put_per_filter_config(route, String.t(), atom(), struct()) :: route
  def put_per_filter_config(%Route{} = route, filter_name, kind, message) do
    config = Map.put(route.typed_per_filter_config, filter_name, Xds.any(kind, message))
    %{route | typed_per_filter_config: config}
  end

  # Header mutations accumulate in call order on routes, virtual hosts and
  # route configurations alike.
  @spec add_request_header(struct(), Pb.Data.HeaderValueOption.t()) :: struct()
  def add_request_header(%{request_headers_to_add: headers} = value, update),
    do: %{value | request_headers_to_add: headers ++ [update]}

  @spec add_response_header(struct(), Pb.Data.HeaderValueOption.t()) :: struct()
  def add_response_header(%{response_headers_to_add: headers} = value, update),
    do: %{value | response_headers_to_add: headers ++ [update]}

  @spec remove_request_header(struct(), String.t()) :: struct()
  def remove_request_header(%{request_headers_to_remove: headers} = value, name),
    do: %{value | request_headers_to_remove: headers ++ [name]}

  @spec remove_response_header(struct(), String.t()) :: struct()
  def remove_response_header(%{response_headers_to_remove: headers} = value, name),
    do: %{value | response_headers_to_remove: headers ++ [name]}

  @doc "A weighted distribution from `{name, weight}` pairs; a bare name weighs 1."
  @spec weighted_clusters([String.t() | {String.t(), non_neg_integer()}]) ::
          Pb.Route.WeightedCluster.t()
  def weighted_clusters(distribution) do
    clusters =
      Enum.map(distribution, fn
        {name, weight} ->
          %Pb.Route.WeightedCluster.ClusterWeight{name: name, weight: uint32(weight)}

        name when is_binary(name) ->
          %Pb.Route.WeightedCluster.ClusterWeight{name: name, weight: uint32(1)}
      end)

    %Pb.Route.WeightedCluster{clusters: clusters}
  end

  @doc """
  A retry policy for the comma-separated `retry_on` conditions: 3 retries of 1
  second each, backing off from 1 to 10 seconds, unless the options say otherwise.
  """
  @spec retry_policy(String.t(), keyword()) :: Pb.Route.RetryPolicy.t()
  def retry_policy(retry_on, opts \\ []) do
    %Pb.Route.RetryPolicy{
      retry_on: retry_on,
      num_retries: uint32(Keyword.get(opts, :num_retries, 3)),
      per_try_timeout: duration(Keyword.get(opts, :per_try_timeout, 1)),
      retry_back_off: %Pb.Route.RetryPolicy.RetryBackOff{
        base_interval: duration(Keyword.get(opts, :base_interval, 1)),
        max_interval: duration(Keyword.get(opts, :max_interval, 10))
      },
      retriable_status_codes: Keyword.get(opts, :retriable_status_codes, []),
      retriable_headers: Keyword.get(opts, :retriable_headers, []),
      retriable_request_headers: Keyword.get(opts, :retriable_request_headers, [])
    }
  end

  @doc """
  A redirect. `:scheme` is `true` (https), `false` (keep the request's) or a
  scheme name; the path is `:path_redirect` (whole path) or `:prefix_rewrite`.
  """
  @spec redirect_action(keyword()) :: Pb.Route.RedirectAction.t()
  def redirect_action(opts \\ []) do
    %Pb.Route.RedirectAction{
      scheme_rewrite_specifier: redirect_scheme(Keyword.get(opts, :scheme, true)),
      host_redirect: Keyword.get(opts, :host, ""),
      port_redirect: Keyword.get(opts, :port, 0),
      path_rewrite_specifier: redirect_path(opts),
      response_code: Keyword.get(opts, :response_code, :TEMPORARY_REDIRECT),
      strip_query: Keyword.get(opts, :strip_query, false)
    }
  end

  def direct_response_action(status, nil), do: %Pb.Route.DirectResponseAction{status: status}

  def direct_response_action(status, %Pb.Data.DataSource{} = body),
    do: %Pb.Route.DirectResponseAction{status: status, body: body}

  def string_matcher(match_type, value) when match_type in [:exact, :prefix, :suffix, :contains],
    do: %Pb.Data.StringMatcher{match_pattern: {match_type, value}}

  def string_matcher(:regex, pattern) when is_binary(pattern),
    do: %Pb.Data.StringMatcher{match_pattern: {:safe_regex, regex_matcher(pattern)}}

  def string_matcher(:regex, %Pb.Data.RegexMatcher{} = matcher),
    do: %Pb.Data.StringMatcher{match_pattern: {:safe_regex, matcher}}

  def regex_matcher(pattern), do: %Pb.Data.RegexMatcher{regex: pattern}

  @doc "A header matcher: `:exists` takes options, `:exact`/`:regex` a value and `:string` a string matcher."
  def header_match(type, name, value_or_opts \\ [], opts \\ [])

  def header_match(:exists, name, opts, _),
    do: %Pb.Data.HeaderMatcher{
      name: name,
      header_match_specifier: {:present_match, true},
      invert_match: invert(opts)
    }

  def header_match(:exact, name, value, opts),
    do: %Pb.Data.HeaderMatcher{
      name: name,
      header_match_specifier: {:exact_match, value},
      invert_match: invert(opts)
    }

  def header_match(:string, name, matcher, opts),
    do: %Pb.Data.HeaderMatcher{
      name: name,
      header_match_specifier: {:string_match, matcher},
      invert_match: invert(opts)
    }

  def header_match(:regex, name, pattern, opts) do
    %Pb.Data.HeaderMatcher{
      name: name,
      header_match_specifier: {:safe_regex_match, regex_matcher(pattern)},
      invert_match: invert(opts)
    }
  end

  def query_present(name, present \\ true),
    do: %Pb.Route.QueryParameterMatcher{
      name: name,
      query_parameter_match_specifier: {:present_match, present}
    }

  def query_match(name, matcher),
    do: %Pb.Route.QueryParameterMatcher{
      name: name,
      query_parameter_match_specifier: {:string_match, matcher}
    }

  def header_value(name, value), do: %Pb.Data.HeaderValue{key: name, value: value}

  @doc "A header mutation: `:append_if_exists_or_add`, `:add_if_not_exists`, `:overwrite_if_exists_or_add` or `:overwrite_if_exists`."
  def header_update(action, header),
    do: %Pb.Data.HeaderValueOption{
      header: header,
      append_action: Map.fetch!(@append_actions, action)
    }

  defdelegate data_source(type, value), to: Xds

  def regex_substitution(pattern, substitution),
    do: %Pb.Data.RegexMatchAndSubstitute{
      pattern: regex_matcher(pattern),
      substitution: substitution
    }

  defp match(path_specifier),
    do: %RouteMatch{path_specifier: path_specifier, case_sensitive: bool(true)}

  defp put_path(%Route{match: %RouteMatch{} = match} = route, path_specifier),
    do: put_match(route, %{match | path_specifier: path_specifier})

  defp put_path(%Route{} = route, path_specifier), do: put_match(route, match(path_specifier))

  defp put_destination(%Route{action: {:route, action}} = route, specifier),
    do: put_action(route, %{action | cluster_specifier: specifier})

  defp put_destination(%Route{} = route, specifier),
    do: put_action(route, route_action(specifier))

  defp update_route_action(%Route{action: {:route, action}} = route, fun),
    do: %{route | action: {:route, fun.(action)}}

  defp update_route_action(%Route{name: name, action: action}, _fun) do
    raise ArgumentError,
          "route #{inspect(name)} has #{describe(action)}: set its cluster before refining the route action"
  end

  defp describe(nil), do: "no action"
  defp describe({kind, _}), do: "a #{kind} action"

  defp invert(opts), do: Keyword.get(opts, :invert, false)

  defp redirect_scheme(value) when is_boolean(value), do: {:https_redirect, value}
  defp redirect_scheme(value) when is_binary(value), do: {:scheme_redirect, value}
  defp redirect_scheme({_, _} = value), do: value

  defp redirect_path(opts) do
    cond do
      Keyword.has_key?(opts, :path_redirect) ->
        {:path_redirect, Keyword.fetch!(opts, :path_redirect)}

      Keyword.has_key?(opts, :prefix_rewrite) ->
        {:prefix_rewrite, Keyword.fetch!(opts, :prefix_rewrite)}

      true ->
        nil
    end
  end
end
