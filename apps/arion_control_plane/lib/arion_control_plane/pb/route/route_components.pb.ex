defmodule Arion.ControlPlane.Pb.Route.RouteAction.ClusterNotFoundResponseCode do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "route.RouteAction.ClusterNotFoundResponseCode",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :SERVICE_UNAVAILABLE, 0
  field :NOT_FOUND, 1
  field :INTERNAL_SERVER_ERROR, 2
end

defmodule Arion.ControlPlane.Pb.Route.RedirectAction.RedirectResponseCode do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "route.RedirectAction.RedirectResponseCode",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :MOVED_PERMANENTLY, 0
  field :FOUND, 1
  field :SEE_OTHER, 2
  field :TEMPORARY_REDIRECT, 3
  field :PERMANENT_REDIRECT, 4
end

defmodule Arion.ControlPlane.Pb.Route.VirtualHost do
  @moduledoc false

  use Protobuf,
    full_name: "route.VirtualHost",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :name, 1, type: :string
  field :domains, 2, repeated: true, type: :string
  field :routes, 3, repeated: true, type: Arion.ControlPlane.Pb.Route.Route

  field :request_headers_to_add, 7,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.HeaderValueOption,
    json_name: "requestHeadersToAdd"

  field :request_headers_to_remove, 13,
    repeated: true,
    type: :string,
    json_name: "requestHeadersToRemove"

  field :response_headers_to_add, 10,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.HeaderValueOption,
    json_name: "responseHeadersToAdd"

  field :response_headers_to_remove, 11,
    repeated: true,
    type: :string,
    json_name: "responseHeadersToRemove"

  field :retry_policy, 16, type: Arion.ControlPlane.Pb.Route.RetryPolicy, json_name: "retryPolicy"
end

defmodule Arion.ControlPlane.Pb.Route.Route.TypedPerFilterConfigEntry do
  @moduledoc false

  use Protobuf,
    full_name: "route.Route.TypedPerFilterConfigEntry",
    map: true,
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: Google.Protobuf.Any
end

defmodule Arion.ControlPlane.Pb.Route.Route do
  @moduledoc false

  use Protobuf, full_name: "route.Route", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  oneof :action, 0

  field :name, 14, type: :string
  field :match, 1, type: Arion.ControlPlane.Pb.Route.RouteMatch
  field :route, 2, type: Arion.ControlPlane.Pb.Route.RouteAction, oneof: 0
  field :redirect, 3, type: Arion.ControlPlane.Pb.Route.RedirectAction, oneof: 0

  field :direct_response, 7,
    type: Arion.ControlPlane.Pb.Route.DirectResponseAction,
    json_name: "directResponse",
    oneof: 0

  field :request_headers_to_add, 9,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.HeaderValueOption,
    json_name: "requestHeadersToAdd"

  field :request_headers_to_remove, 12,
    repeated: true,
    type: :string,
    json_name: "requestHeadersToRemove"

  field :response_headers_to_add, 10,
    repeated: true,
    type: Arion.ControlPlane.Pb.Data.HeaderValueOption,
    json_name: "responseHeadersToAdd"

  field :response_headers_to_remove, 11,
    repeated: true,
    type: :string,
    json_name: "responseHeadersToRemove"

  field :typed_per_filter_config, 13,
    repeated: true,
    type: Arion.ControlPlane.Pb.Route.Route.TypedPerFilterConfigEntry,
    json_name: "typedPerFilterConfig",
    map: true
end

defmodule Arion.ControlPlane.Pb.Route.RouteMatch do
  @moduledoc false

  use Protobuf,
    full_name: "route.RouteMatch",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :path_specifier, 0

  field :prefix, 1, type: :string, oneof: 0
  field :path, 2, type: :string, oneof: 0

  field :safe_regex, 10,
    type: Arion.ControlPlane.Pb.Data.RegexMatcher,
    json_name: "safeRegex",
    oneof: 0

  field :path_separated_prefix, 14, type: :string, json_name: "pathSeparatedPrefix", oneof: 0
  field :case_sensitive, 4, type: Google.Protobuf.BoolValue, json_name: "caseSensitive"
  field :headers, 6, repeated: true, type: Arion.ControlPlane.Pb.Data.HeaderMatcher

  field :query_parameters, 7,
    repeated: true,
    type: Arion.ControlPlane.Pb.Route.QueryParameterMatcher,
    json_name: "queryParameters"
end

defmodule Arion.ControlPlane.Pb.Route.QueryParameterMatcher do
  @moduledoc false

  use Protobuf,
    full_name: "route.QueryParameterMatcher",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :query_parameter_match_specifier, 0

  field :name, 1, type: :string

  field :string_match, 5,
    type: Arion.ControlPlane.Pb.Data.StringMatcher,
    json_name: "stringMatch",
    oneof: 0

  field :present_match, 6, type: :bool, json_name: "presentMatch", oneof: 0
end

defmodule Arion.ControlPlane.Pb.Route.RouteAction.RequestMirrorPolicy do
  @moduledoc false

  use Protobuf,
    full_name: "route.RouteAction.RequestMirrorPolicy",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :cluster, 1, type: :string

  field :runtime_fraction, 3,
    type: Arion.ControlPlane.Pb.Data.RuntimeFractionalPercent,
    json_name: "runtimeFraction"
end

defmodule Arion.ControlPlane.Pb.Route.RouteAction do
  @moduledoc false

  use Protobuf,
    full_name: "route.RouteAction",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :cluster_specifier, 0

  field :cluster, 1, type: :string, oneof: 0
  field :cluster_header, 2, type: :string, json_name: "clusterHeader", oneof: 0

  field :weighted_clusters, 3,
    type: Arion.ControlPlane.Pb.Route.WeightedCluster,
    json_name: "weightedClusters",
    oneof: 0

  field :cluster_not_found_response_code, 20,
    type: Arion.ControlPlane.Pb.Route.RouteAction.ClusterNotFoundResponseCode,
    json_name: "clusterNotFoundResponseCode",
    enum: true

  field :prefix_rewrite, 5, type: :string, json_name: "prefixRewrite"

  field :regex_rewrite, 32,
    type: Arion.ControlPlane.Pb.Data.RegexMatchAndSubstitute,
    json_name: "regexRewrite"

  field :timeout, 8, type: Google.Protobuf.Duration
  field :retry_policy, 9, type: Arion.ControlPlane.Pb.Route.RetryPolicy, json_name: "retryPolicy"
  field :priority, 11, type: Arion.ControlPlane.Pb.Data.RoutingPriority, enum: true

  field :hash_policy, 15,
    repeated: true,
    type: Arion.ControlPlane.Pb.Route.HashPolicy,
    json_name: "hashPolicy"

  field :upgrade_configs, 25,
    repeated: true,
    type: Arion.ControlPlane.Pb.Route.UpgradeConfig,
    json_name: "upgradeConfigs"
end

defmodule Arion.ControlPlane.Pb.Route.UpgradeConfig.ConnectConfig do
  @moduledoc false

  use Protobuf,
    full_name: "route.UpgradeConfig.ConnectConfig",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :proxy_protocol_config, 1,
    type: Arion.ControlPlane.Pb.Data.ProxyProtocolConfig,
    json_name: "proxyProtocolConfig"

  field :allow_post, 2, type: :bool, json_name: "allowPost"
end

defmodule Arion.ControlPlane.Pb.Route.UpgradeConfig do
  @moduledoc false

  use Protobuf,
    full_name: "route.UpgradeConfig",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :upgrade_type, 1, type: :string, json_name: "upgradeType"
  field :enabled, 2, type: Google.Protobuf.BoolValue

  field :connect_config, 3,
    type: Arion.ControlPlane.Pb.Route.UpgradeConfig.ConnectConfig,
    json_name: "connectConfig"
end

defmodule Arion.ControlPlane.Pb.Route.HashPolicy.Header do
  @moduledoc false

  use Protobuf,
    full_name: "route.HashPolicy.Header",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :header_name, 1, type: :string, json_name: "headerName"
end

defmodule Arion.ControlPlane.Pb.Route.HashPolicy.CookieAttribute do
  @moduledoc false

  use Protobuf,
    full_name: "route.HashPolicy.CookieAttribute",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :name, 1, type: :string
  field :value, 2, type: :string
end

defmodule Arion.ControlPlane.Pb.Route.HashPolicy.Cookie do
  @moduledoc false

  use Protobuf,
    full_name: "route.HashPolicy.Cookie",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :name, 1, type: :string
  field :ttl, 2, type: Google.Protobuf.Duration
  field :path, 3, type: :string

  field :attributes, 4,
    repeated: true,
    type: Arion.ControlPlane.Pb.Route.HashPolicy.CookieAttribute
end

defmodule Arion.ControlPlane.Pb.Route.HashPolicy.ConnectionProperties do
  @moduledoc false

  use Protobuf,
    full_name: "route.HashPolicy.ConnectionProperties",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :source_ip, 1, type: :bool, json_name: "sourceIp"
end

defmodule Arion.ControlPlane.Pb.Route.HashPolicy.QueryParameter do
  @moduledoc false

  use Protobuf,
    full_name: "route.HashPolicy.QueryParameter",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :name, 1, type: :string
end

defmodule Arion.ControlPlane.Pb.Route.HashPolicy do
  @moduledoc false

  use Protobuf,
    full_name: "route.HashPolicy",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :policy_specifier, 0

  field :header, 1, type: Arion.ControlPlane.Pb.Route.HashPolicy.Header, oneof: 0
  field :cookie, 2, type: Arion.ControlPlane.Pb.Route.HashPolicy.Cookie, oneof: 0

  field :connection_properties, 3,
    type: Arion.ControlPlane.Pb.Route.HashPolicy.ConnectionProperties,
    json_name: "connectionProperties",
    oneof: 0

  field :query_parameter, 5,
    type: Arion.ControlPlane.Pb.Route.HashPolicy.QueryParameter,
    json_name: "queryParameter",
    oneof: 0

  field :terminal, 4, type: :bool
end

defmodule Arion.ControlPlane.Pb.Route.RedirectAction do
  @moduledoc false

  use Protobuf,
    full_name: "route.RedirectAction",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :scheme_rewrite_specifier, 0

  oneof :path_rewrite_specifier, 1

  field :https_redirect, 4, type: :bool, json_name: "httpsRedirect", oneof: 0
  field :scheme_redirect, 7, type: :string, json_name: "schemeRedirect", oneof: 0
  field :host_redirect, 1, type: :string, json_name: "hostRedirect"
  field :port_redirect, 8, type: :uint32, json_name: "portRedirect"
  field :path_redirect, 2, type: :string, json_name: "pathRedirect", oneof: 1
  field :prefix_rewrite, 5, type: :string, json_name: "prefixRewrite", oneof: 1

  field :regex_rewrite, 9,
    type: Arion.ControlPlane.Pb.Data.RegexMatchAndSubstitute,
    json_name: "regexRewrite",
    oneof: 1

  field :response_code, 3,
    type: Arion.ControlPlane.Pb.Route.RedirectAction.RedirectResponseCode,
    json_name: "responseCode",
    enum: true

  field :strip_query, 6, type: :bool, json_name: "stripQuery"
end

defmodule Arion.ControlPlane.Pb.Route.DirectResponseAction do
  @moduledoc false

  use Protobuf,
    full_name: "route.DirectResponseAction",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :status, 1, type: :uint32
  field :body, 2, type: Arion.ControlPlane.Pb.Data.DataSource
end

defmodule Arion.ControlPlane.Pb.Route.WeightedCluster.ClusterWeight do
  @moduledoc false

  use Protobuf,
    full_name: "route.WeightedCluster.ClusterWeight",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :name, 1, type: :string
  field :weight, 2, type: Google.Protobuf.UInt32Value
end

defmodule Arion.ControlPlane.Pb.Route.WeightedCluster do
  @moduledoc false

  use Protobuf,
    full_name: "route.WeightedCluster",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :clusters, 1,
    repeated: true,
    type: Arion.ControlPlane.Pb.Route.WeightedCluster.ClusterWeight
end
