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

defmodule Arion.CtlTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Arion.ControlPlane.{Pb, Service}
  alias Arion.ControlPlane.Helpers.{Cluster, Cors, FilterChain, Hcm, Listener, McpGateway}
  alias Arion.ControlPlane.Helpers.{Route, RouteConfig, VirtualHost}
  alias Arion.ControlPlane.Xds.ResourceTypes
  alias Arion.Ctl.{CLI, Codec, Manifest, Store}

  defp cluster(name \\ "upstream", fleet \\ "arion") do
    %{
      "apiVersion" => "ctl.arion.io/v1alpha1",
      "kind" => "Cluster",
      "metadata" => %{"name" => name, "fleet" => fleet},
      "spec" => %{"type" => "STATIC", "connectTimeout" => "1s"}
    }
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "arion-ctl-test-#{System.unique_integer([:positive])}")
    start_supervised!({Arion.ControlPlane, serve?: false})
    start_supervised!({Store, state_dir: dir})
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "native YAML decodes duration, enums, name and default fleet" do
    yaml = """
    apiVersion: ctl.arion.io/v1alpha1
    kind: Cluster
    metadata:
      name: upstream
    spec:
      type: STATIC
      connect_timeout: 1.5s
    """

    assert {:ok, [entry]} = Manifest.decode(yaml)
    assert entry.id == {"arion", :cluster, "upstream"}
    assert entry.payload.name == "upstream"

    assert entry.payload.connect_timeout == %Google.Protobuf.Duration{
             seconds: 1,
             nanos: 500_000_000
           }

    assert entry.payload.cluster_discovery_type == {:type, :STATIC}
  end

  test "a YAML stream decodes every document" do
    yaml = """
    apiVersion: ctl.arion.io/v1alpha1
    kind: Cluster
    metadata: {name: a}
    spec: {type: STATIC}
    ---
    apiVersion: ctl.arion.io/v1alpha1
    kind: ClusterLoadAssignment
    metadata: {name: a}
    spec: {clusterName: a}
    """

    assert {:ok, [cluster, assignment]} = Manifest.decode(yaml)
    assert cluster.id == {"arion", :cluster, "a"}
    assert assignment.id == {"arion", :load_assignment, "a"}
    assert assignment.payload == %Pb.Endpoint.ClusterLoadAssignment{cluster_name: "a"}
  end

  test "nested Envoy and Arion Any types preserve wire URLs and payloads" do
    listener =
      Codec.decode!(:listener, %{
        "name" => "listener",
        "filterChains" => [
          %{
            "filters" => [
              %{
                "name" => "http",
                "typedConfig" => %{
                  "@type" =>
                    "type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager",
                  "statPrefix" => "http",
                  "httpFilters" => [
                    %{
                      "name" => "mcp",
                      "typedConfig" => %{
                        "@type" =>
                          "type.googleapis.com/arion.extensions.filters.http.mcp.mcp_gateway.v3.McpGateway",
                        "serverInfo" => %{"name" => "demo", "version" => "1"},
                        "toolsMode" => %{}
                      }
                    }
                  ]
                }
              }
            ]
          }
        ]
      })

    [{:typed_config, hcm_any}] =
      for chain <- listener.filter_chains, filter <- chain.filters, do: filter.config_type

    hcm = Protobuf.decode(hcm_any.value, Pb.Filter.HttpConnectionManager)
    [{:typed_config, mcp_any}] = Enum.map(hcm.http_filters, & &1.config_type)
    assert mcp_any.type_url =~ "/arion.extensions."

    assert Protobuf.decode(mcp_any.value, Pb.Data.Extensions.McpGateway).server_info.name ==
             "demo"
  end

  test "map Any values and oneofs decode" do
    cluster =
      Codec.decode!(:cluster, %{
        "name" => "h2",
        "type" => "STATIC",
        "typed_extension_protocol_options" => %{
          "envoy.extensions.upstreams.http.v3.HttpProtocolOptions" => %{
            "@type" =>
              "type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions",
            "explicitHttpConfig" => %{"http2ProtocolOptions" => %{}}
          }
        }
      })

    assert map_size(cluster.typed_extension_protocol_options) == 1
  end

  test "unknown fields are rejected everywhere, including inside well-known types" do
    assert_raise ArgumentError, ~r/spec: unknown field "typo"/, fn ->
      Codec.decode!(:cluster, %{"name" => "a", "typo" => true})
    end

    assert_raise ArgumentError, ~r/spec.connect_timeout: unknown field "bogus"/, fn ->
      Codec.decode!(:cluster, %{
        "name" => "a",
        "connectTimeout" => %{"seconds" => 1, "bogus" => true}
      })
    end

    assert %{connect_timeout: %{seconds: 1}} =
             Codec.decode!(:cluster, %{"name" => "a", "connectTimeout" => %{"seconds" => 1}})

    assert_raise ArgumentError, ~r/spec.filter_chains\[1\].filters\[0\]: unknown field/, fn ->
      Codec.decode!(:listener, %{"filterChains" => [%{}, %{"filters" => [%{"typo" => 1}]}]})
    end
  end

  test "conflicting oneofs, names, kinds and URLs fail without mutation" do
    assert {:ok, _} = Arion.Ctl.apply([cluster()])
    invalid = put_in(cluster("bad"), ["spec", "typo"], true)
    assert {:error, _} = Arion.Ctl.apply([cluster("second"), invalid])
    assert Enum.map(Arion.Ctl.get(), & &1["metadata"]["name"]) == ["upstream"]

    assert {:error, "metadata.name and spec name disagree"} =
             Manifest.decode([put_in(cluster(), ["spec", "name"], "other")])

    assert {:error, "unsupported kind \"Unknown\""} =
             Manifest.decode([Map.put(cluster(), "kind", "Unknown")])

    assert {:error, "duplicate resource identity in input"} =
             Manifest.decode([cluster(), cluster()])

    assert {:error, "metadata: unknown field \"labels\""} =
             Manifest.decode([put_in(cluster(), ["metadata", "labels"], %{})])

    assert_raise ArgumentError, ~r/multiple values for oneof/, fn ->
      Codec.decode!(:route, %{
        "virtualHosts" => [%{"routes" => [%{"match" => %{"prefix" => "/", "path" => "/x"}}]}]
      })
    end

    assert_raise ArgumentError, ~r/unsupported Any type/, fn ->
      Codec.decode!(:listener, %{
        "filterChains" => [
          %{"filters" => [%{"typedConfig" => %{"@type" => "type.googleapis.com/unknown.Type"}}]}
        ]
      })
    end
  end

  test "a name field is accepted in one spelling, filled in when omitted, and rejected in both" do
    assignment = fn spec ->
      %{
        "apiVersion" => "ctl.arion.io/v1alpha1",
        "kind" => "ClusterLoadAssignment",
        "metadata" => %{"name" => "a"},
        "spec" => spec
      }
    end

    for spec <- [%{}, %{"cluster_name" => "a"}, %{"clusterName" => "a"}, %{"clusterName" => nil}] do
      assert {:ok, [entry]} = Manifest.decode([assignment.(spec)])
      assert entry.id == {"arion", :load_assignment, "a"}
      assert entry.payload.cluster_name == "a"
    end

    both = "spec: cluster_name and clusterName are the same field"

    assert {:error, ^both} =
             Manifest.decode([assignment.(%{"cluster_name" => "a", "clusterName" => "a"})])

    assert {:error, ^both} =
             Manifest.decode([assignment.(%{"cluster_name" => "a", "clusterName" => "b"})])

    assert {:error, ^both} =
             Manifest.decode([assignment.(%{"cluster_name" => nil, "clusterName" => "a"})])

    assert {:error, "metadata.name and spec clusterName disagree"} =
             Manifest.decode([assignment.(%{"clusterName" => "b"})])

    # One invalid document rejects the batch: nothing is saved or published.
    assert {:ok, _} = Arion.Ctl.apply([cluster()])
    Service.subscribe(self(), "arion", ResourceTypes.type_url!(:cluster), %{})
    assert_receive {:"$gen_cast", {:publish, :cluster, [_]}}
    before = Arion.Ctl.get()

    assert {:error, ^both} =
             Arion.Ctl.apply([
               cluster("second"),
               assignment.(%{"cluster_name" => "a", "clusterName" => "a"})
             ])

    assert Arion.Ctl.get() == before
    refute_receive {:"$gen_cast", _}
  end

  test "a document missing its envelope fails without echoing its contents" do
    secret = %{
      "apiVersion" => "ctl.arion.io/v1alpha1",
      "kind" => "Secret",
      "spec" => %{
        "name" => "tls",
        "tlsCertificate" => %{"privateKey" => %{"inlineString" => "PRIVATE-KEY-PEM"}}
      }
    }

    assert {:error, message} = Manifest.decode([secret])
    assert message == "document: missing metadata"
    refute message =~ "PRIVATE"
  end

  test "apply persists atomically, recovers on restart and isolates fleets", %{dir: dir} do
    assert {:ok, _} = Arion.Ctl.apply([cluster("a"), cluster("b", "other")])
    before = File.read!(Path.join(dir, "state.json"))
    assert {:error, _} = Arion.Ctl.apply([%{}])
    assert File.read!(Path.join(dir, "state.json")) == before
    stop_supervised(Store)
    Service.replace("arion", [])
    start_supervised!({Store, state_dir: dir})
    assert length(Arion.Ctl.get()) == 2
    assert %{cluster: %{"a" => _}} = Service.resources("arion")
    assert %{cluster: %{"b" => _}} = Service.resources("other")
  end

  test "disk failure keeps previous resources active", %{dir: dir} do
    assert {:ok, _} = Arion.Ctl.apply([cluster()])
    File.mkdir!(Path.join(dir, "state.json.tmp"))
    assert {:error, "could not persist desired state: " <> _} = Arion.Ctl.apply([cluster("new")])
    assert length(Arion.Ctl.get()) == 1
  end

  test "delete publishes a removal, unchanged apply publishes nothing, and an empty fleet is retired" do
    assert {:ok, _} = Arion.Ctl.apply([cluster(), cluster("c", "other")])
    Service.subscribe(self(), "arion", ResourceTypes.type_url!(:cluster), %{})
    assert_receive {:"$gen_cast", {:publish, :cluster, [_]}}
    assert {:ok, _} = Arion.Ctl.apply([cluster()])
    refute_receive {:"$gen_cast", {:publish, _, _}}

    assert {:ok, _} = Arion.Ctl.delete("Cluster", "upstream")
    assert_receive {:"$gen_cast", {:unpublish, :cluster, ["upstream"]}}
    assert {:error, "unsupported kind \"cluster\""} = Arion.Ctl.delete("cluster", "upstream")

    # The subscribed fleet is kept; the other one has no resources and no proxy.
    assert {:ok, %{resources: 0}} = Arion.Ctl.delete("Cluster", "c", "other")
    assert Service.list_fleets() == ["arion"]
  end

  test "an unchanged apply or delete neither writes the snapshot nor replaces the fleets", %{
    dir: dir
  } do
    assert {:ok, %{resources: 2}} = Arion.Ctl.apply([cluster(), cluster("c", "other")])
    monitors = :sys.get_state(Store).monitors
    snapshot = Path.join(dir, "state.json")
    File.mkdir!(snapshot <> ".tmp")

    assert {:ok, %{resources: 2}} = Arion.Ctl.apply([cluster()])
    assert {:ok, %{resources: 2}} = Arion.Ctl.delete("Cluster", "absent")
    assert :sys.get_state(Store).monitors == monitors
    assert {:error, "could not persist desired state: " <> _} = Arion.Ctl.apply([cluster("new")])

    # A changed apply still persists and publishes, and recovery still works.
    File.rmdir!(snapshot <> ".tmp")
    assert {:ok, %{resources: 3}} = Arion.Ctl.apply([cluster("new")])
    assert :sys.get_state(Store).monitors != monitors
    assert Jason.decode!(File.read!(snapshot))["resources"] |> length() == 3

    assert {:ok, %{resources: 3}} = Arion.Ctl.apply([cluster("new")])
    pid = Service.ensure("arion")
    Process.exit(pid, :kill)

    assert eventually(fn ->
             Service.ensure("arion") != pid and
               Map.has_key?(Service.resources("arion").cluster, "new")
           end)
  end

  test "helper-built resources apply durably, export, reapply and survive a restart", %{dir: dir} do
    cluster =
      "backend"
      |> Cluster.static("127.0.0.1", [8080], connect_timeout: 2)
      |> Cluster.put_http_protocol_options(Cluster.http2_options())

    route = "all" |> Route.new() |> Route.to_cluster("backend") |> Route.timeout(30)
    host = VirtualHost.new("all") |> VirtualHost.add_route(route)
    routes = RouteConfig.new("routes") |> RouteConfig.add_virtual_host(host)
    hcm = Hcm.new(codec_type: :HTTP1) |> Hcm.route_config(routes) |> Hcm.add_filter(Cors.filter())
    chain = FilterChain.new("http") |> FilterChain.add_hcm(hcm)

    listener =
      Listener.new("http", Listener.local_address(8081)) |> Listener.add_filter_chain(chain)

    tool =
      McpGateway.tool(
        "docs",
        "search",
        "Search",
        McpGateway.rest_backend("backend", "POST", "/s")
      )

    tool_resource = McpGateway.tool_resource("gw", "gateway", tool)

    resources = [cluster: cluster, listener: listener, mcp_tool: tool_resource]
    assert {:ok, %{resources: 3}} = Arion.Ctl.apply_resources(resources)

    # The fleet holds what the Store published: `{name, payload}` pairs.
    published = fn ->
      %{cluster: c, listener: l, mcp_tool: t} = Service.resources("arion")
      {c["backend"], l["http"], t["gw/gateway/docs.search"]}
    end

    # Durations, wrappers, oneofs, the Any map value and the nested Any all round-trip.
    expected = {{"backend", cluster}, {"http", listener}, tool_resource}
    assert published.() == expected
    docs = Arion.Ctl.get()
    assert Enum.map(docs, & &1["kind"]) == ["Cluster", "Listener", "McpTool"]
    assert [%{"spec" => %{"connectTimeout" => "2s", "type" => "STATIC"}} | _] = docs
    assert {:ok, _} = Arion.Ctl.validate(docs)

    assert {:ok, %{resources: 0}} = Arion.Ctl.delete_documents(docs)
    assert {:ok, %{resources: 3}} = Arion.Ctl.apply(docs)
    assert {:ok, %{resources: 3}} = Arion.Ctl.apply_resources(resources)
    assert published.() == expected

    stop_supervised(Store)
    Service.replace("arion", [])
    start_supervised!({Store, state_dir: dir})
    assert published.() == expected
    assert Arion.Ctl.get() == docs

    # An explicit name fills in a default payload name, as a manifest would.
    assert {:ok, _} =
             Arion.Ctl.apply_resources([cluster: {"named", %Pb.Cluster.Cluster{}}], fleet: "b")

    assert %{cluster: %{"named" => {"named", %{name: "named"}}}} = Service.resources("b")
  end

  test "an invalid helper-built batch or a persistence failure changes nothing", %{dir: dir} do
    cluster = Cluster.static("backend", "127.0.0.1", [8080])
    assert {:ok, _} = Arion.Ctl.apply_resources(cluster: cluster)
    snapshot = Path.join(dir, "state.json")
    before = {Arion.Ctl.get(), File.read!(snapshot), Service.resources("arion")}
    unknown = %Google.Protobuf.Any{type_url: "type.googleapis.com/unknown.Type"}
    socket = %Pb.Data.TransportSocket{config_type: {:typed_config, unknown}}

    for {bad, message} <- [
          {{:tcp_proxy, %Pb.Filter.TcpProxy{}}, "not a discovery resource kind"},
          {{:cluster, %Pb.Listener.Listener{name: "x"}}, "cluster expects"},
          {{:cluster, %Pb.Cluster.Cluster{name: ""}}, "no discovery name"},
          {{:cluster, {"other", cluster}}, "metadata.name and spec name disagree"},
          {{:cluster, cluster}, "duplicate resource identity"},
          {{:cluster, %Pb.Cluster.Cluster{name: "x", transport_socket: socket}},
           "unsupported Any type"},
          {:not_a_pair, "expected {kind, resource} pairs"}
        ] do
      assert {:error, reason} = Arion.Ctl.apply_resources([{:cluster, cluster}, bad])
      assert reason =~ message
    end

    assert {:error, "metadata.fleet must be a nonempty string"} =
             Arion.Ctl.apply_resources([cluster: cluster], fleet: "")

    File.mkdir!(snapshot <> ".tmp")

    assert {:error, "could not persist desired state: " <> _} =
             Arion.Ctl.apply_resources(cluster: Cluster.static("new", "127.0.0.1", [1]))

    assert {Arion.Ctl.get(), File.read!(snapshot), Service.resources("arion")} == before
  end

  test "status counts resources per running fleet" do
    assert {:ok, _} = Arion.Ctl.apply([cluster("a"), cluster("b"), cluster("c", "other")])

    assert Arion.Ctl.status() == %{
             "arion" => %{resources: 2, clients: %{}},
             "other" => %{resources: 1, clients: %{}}
           }
  end

  test "CLI get export validates and applies from a file", %{dir: dir} do
    assert {:ok, %{resources: 2}} =
             Arion.Ctl.apply([cluster("upstream"), cluster("second", "other")])

    {:ok, docs} = CLI.execute(%{"op" => "get", "fleet" => nil})
    export_path = Path.join(dir, "resources.json")
    File.write!(export_path, Jason.encode!(docs))

    assert {:local, %{valid: true, resources: 2}} = CLI.request(["validate", "-f", export_path])
    assert {:ok, %{resources: 0}} = Arion.Ctl.delete_documents(docs)

    assert {:remote, %{"op" => "apply", "documents" => resources}} =
             CLI.request(["apply", "-f", export_path])

    assert {:ok, %{resources: 2}} = CLI.execute(%{"op" => "apply", "documents" => resources})
    assert Arion.Ctl.get() == docs

    yaml_path = Path.join(dir, "resource.yaml")

    File.write!(yaml_path, """
    apiVersion: ctl.arion.io/v1alpha1
    kind: Cluster
    metadata:
      name: upstream
    spec:
      type: STATIC
      connectTimeout: 1s
    """)

    assert {:local, %{valid: true, resources: 1}} = CLI.request(["validate", "-f", yaml_path])

    assert {:remote, %{"op" => "apply", "documents" => yaml_resources}} =
             CLI.request(["apply", "-f", yaml_path])

    assert {:ok, %{resources: 2}} = CLI.execute(%{"op" => "apply", "documents" => yaml_resources})
  end

  test "CLI dispatch and IEx use the same durable API" do
    assert {:ok, _} = CLI.execute(%{"op" => "apply", "documents" => [cluster()]})
    assert {:ok, docs} = CLI.execute(%{"op" => "get", "fleet" => nil})
    assert docs == Arion.Ctl.get()

    assert {:ok, _} =
             CLI.execute(%{
               "op" => "delete_name",
               "kind" => "Cluster",
               "name" => "upstream",
               "fleet" => "arion"
             })

    assert [] = Arion.Ctl.get()
  end

  test "CLI usage and file errors go to stderr with a nonzero status", %{dir: dir} do
    assert capture_io(:stderr, fn -> assert CLI.main(["frobnicate"]) == 1 end) =~
             "arionctl serve | shell"

    assert {:error, "/nonexistent: no such file or directory"} =
             CLI.request(["apply", "-f", "/nonexistent"])

    assert {:error, "/nonexistent: no such file or directory"} =
             Arion.Ctl.apply_file("/nonexistent")

    bad = Path.join(dir, "bad.yaml")
    File.write!(bad, "apiVersion: nope\n")
    assert {:error, message} = CLI.request(["validate", "-f", bad])
    assert message == "#{bad}: document: missing kind"

    assert capture_io(:stderr, fn -> assert CLI.main(["validate", "-f", bad]) == 1 end) =~
             "missing kind"
  end

  test "a crashed fleet is restored from the snapshot" do
    assert {:ok, _} = Arion.Ctl.apply([cluster()])
    pid = Service.ensure("arion")
    Process.exit(pid, :kill)

    assert eventually(fn ->
             Service.ensure("arion") != pid and
               Map.has_key?(Service.resources("arion").cluster, "upstream")
           end)
  end

  test "corrupt snapshots fail startup", %{dir: dir} do
    stop_supervised(Store)
    File.write!(Path.join(dir, "state.json"), "bad json")

    assert {:error, {{:state_restore_failed, message}, _}} =
             start_supervised({Store, state_dir: dir})

    assert message =~ "not a version 1 snapshot"
  end

  defp eventually(fun, attempts \\ 50) do
    result =
      try do
        fun.()
      catch
        :exit, _ -> false
      end

    cond do
      result -> true
      attempts == 0 -> false
      true -> Process.sleep(10) && eventually(fun, attempts - 1)
    end
  end
end
