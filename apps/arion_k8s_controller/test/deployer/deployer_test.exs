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

defmodule Arion.K8sController.DeployerTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Arion.K8sController.{Config, Fixtures, Ir}
  alias Arion.K8sController.Kube.Gvk
  alias Arion.K8sController.Deployer.{Bootstrap, Deployer, Objects, Params}
  alias Arion.K8sController.Reconcile.Resolver

  defp config, do: %Config{controller_name: Fixtures.controller_name()}

  defp gateway do
    %Ir.Gateway{
      namespace: "default",
      name: "demo",
      uid: "uid-123",
      generation: 1,
      class_name: "arion",
      listeners: [
        %Ir.Listener{name: "http", port: 80, protocol: :http},
        %Ir.Listener{name: "https", port: 443, protocol: :https}
      ]
    }
  end

  defp by_kind(objects, kind), do: Enum.find(objects, &(&1["kind"] == kind))

  describe "Objects.build/3" do
    test "produces the four provisioned objects, all owned by the Gateway" do
      objects = Objects.build(gateway(), %Params{image: "arion:latest"}, config())

      assert Enum.map(objects, & &1["kind"]) ==
               ["ConfigMap", "ServiceAccount", "Deployment", "Service"]

      for obj <- objects do
        assert obj["metadata"]["name"] == "gateway-default-demo"
        assert obj["metadata"]["namespace"] == "default"
        [owner] = obj["metadata"]["ownerReferences"]
        assert owner["kind"] == "Gateway"
        assert owner["uid"] == "uid-123"
        assert owner["controller"] == true
      end
    end

    test "a long Gateway name gives valid object names and label values" do
      long = %{
        gateway()
        | namespace: "gateway-conformance-infra",
          name: String.duplicate("a", 70)
      }

      objects = Objects.build(long, %Params{image: "arion:latest"}, config())
      dep = by_kind(objects, "Deployment")

      pod_labels = [
        dep["spec"]["selector"]["matchLabels"],
        dep["spec"]["template"]["metadata"]["labels"]
      ]

      for obj <- objects do
        assert obj["metadata"]["name"] =~ ~r/^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$/
      end

      for labels <- pod_labels ++ Enum.map(objects, & &1["metadata"]["labels"]),
          value <- Map.values(labels),
          do: assert(byte_size(value) <= 63)
    end

    test "infrastructure labels and annotations reach every object and the pods" do
      params = %Params{
        image: "arion:latest",
        labels: %{"infra-label" => "a"},
        annotations: %{"infra-annotation" => "b"}
      }

      objects = Objects.build(gateway(), params, config())

      for obj <- objects do
        assert obj["metadata"]["labels"]["infra-label"] == "a"
        assert obj["metadata"]["labels"]["gateway.networking.k8s.io/gateway-name"] == "demo"
        assert obj["metadata"]["annotations"]["infra-annotation"] == "b"
      end

      template = by_kind(objects, "Deployment")["spec"]["template"]["metadata"]
      assert template["labels"]["infra-label"] == "a"
      assert template["labels"]["gateway.networking.k8s.io/gateway-name"] == "demo"
      assert template["annotations"]["infra-annotation"] == "b"
      assert template["annotations"]["arion.io/bootstrap-sha256"]
    end

    test "Deployment carries image, replicas, listener ports and the bootstrap mount" do
      params = %Params{image: "arion:2.0", replicas: 3}
      dep = Objects.build(gateway(), params, config()) |> by_kind("Deployment")

      assert dep["spec"]["replicas"] == 3
      [container] = dep["spec"]["template"]["spec"]["containers"]
      assert container["image"] == "arion:2.0"
      assert container["command"] == ["/arion"]
      assert container["args"] == ["--with-envoy-bootstrap", "/etc/arion/bootstrap.json"]
      assert Enum.map(container["ports"], & &1["containerPort"]) == [80, 443]
      assert Enum.any?(container["volumeMounts"], &(&1["mountPath"] == "/etc/arion"))
    end

    test "Service uses the params service type and exposes the listener ports" do
      params = %Params{image: "arion:latest", service_type: "NodePort"}
      svc = Objects.build(gateway(), params, config()) |> by_kind("Service")

      assert svc["spec"]["type"] == "NodePort"
      assert Enum.map(svc["spec"]["ports"], & &1["port"]) == [80, 443]
    end

    test "ConfigMap embeds a valid bootstrap pinned to the Gateway's xDS namespace" do
      cm =
        Objects.build(gateway(), %Params{image: "arion:latest"}, config()) |> by_kind("ConfigMap")

      bootstrap = Jason.decode!(cm["data"]["bootstrap.json"])

      assert bootstrap["node"]["cluster"] == "gateway/default/demo"

      assert bootstrap["dynamic_resources"] == %{
               "ads_config" => %{
                 "grpc_services" => [%{"envoy_grpc" => %{"cluster_name" => "xds_cluster"}}]
               }
             }
    end

    test "a bootstrap change rolls the Deployment's pods" do
      template_annotations = fn config ->
        dep =
          Objects.build(gateway(), %Params{image: "arion:latest"}, config)
          |> by_kind("Deployment")

        dep["spec"]["template"]["metadata"]["annotations"]
      end

      assert template_annotations.(config()) == template_annotations.(config())

      assert template_annotations.(config()) !=
               template_annotations.(%{config() | control_plane_port: 50052})
    end
  end

  describe "Deployer.objects/2" do
    test "a Gateway with an unsupported parametersRef is not provisioned" do
      for {ref, count} <- [{%{"group" => "invalid.io", "kind" => "Invalid"}, 0}, {nil, 4}] do
        gateway =
          put_in(Fixtures.gateway(), ["spec", "infrastructure"], %{"parametersRef" => ref})

        snapshot = Fixtures.snapshot([Fixtures.gateway_class(), gateway])

        graph = Resolver.resolve(snapshot, Fixtures.controller_name())
        assert length(Deployer.objects(graph, config())) == count
      end
    end
  end

  describe "Deployer" do
    @name "gateway-default-demo"
    @deployment_key {"Deployment", "default", @name}

    setup do
      snapshot = Fixtures.snapshot([Fixtures.gateway_class(), Fixtures.gateway()])
      graph = Resolver.resolve(snapshot, Fixtures.controller_name())
      %{snapshot: snapshot, graph: graph, live: live(graph, snapshot)}
    end

    test "a failed apply is retried until it succeeds without a new reconcile", ctx do
      deployer = start_deployer(apply: %{"Deployment" => [{:error, :down}, {:error, :down}]})
      Deployer.reconcile(deployer, ctx.graph, ctx.snapshot)

      assert applied(4) == ["ConfigMap", "ServiceAccount", "Deployment", "Service"]
      assert applied(1) == ["Deployment"]
      assert applied(1) == ["Deployment"]
      refute_receive {:applied, _}, 50
      assert :sys.get_state(deployer).pending == %{}
    end

    test "a partial failure leaves only the failed sibling pending", ctx do
      deployer = start_deployer(apply: %{"Service" => [{:error, :down}]}, backoff_ms: 100)
      Deployer.reconcile(deployer, ctx.graph, ctx.snapshot)
      assert applied(4) == ["ConfigMap", "ServiceAccount", "Deployment", "Service"]

      state = :sys.get_state(deployer)

      assert Enum.sort(Map.keys(state.applied)) ==
               keys(["ConfigMap", "Deployment", "ServiceAccount"])

      assert Map.keys(state.pending) == keys(["Service"])

      assert applied(1) == ["Service"]
      assert map_size(:sys.get_state(deployer).applied) == 4
    end

    test "new desired content replaces a pending retry", ctx do
      deployer = start_deployer(apply: %{"Deployment" => [{:error, :down}]})
      Deployer.reconcile(deployer, ctx.graph, ctx.snapshot)
      assert applied(4) == ["ConfigMap", "ServiceAccount", "Deployment", "Service"]

      listener = %{"name" => "alt", "port" => 8080, "protocol" => "HTTP"}
      gateway = update_in(Fixtures.gateway(), ["spec", "listeners"], &(&1 ++ [listener]))
      snapshot = Fixtures.snapshot([Fixtures.gateway_class(), gateway])

      Deployer.reconcile(
        deployer,
        Resolver.resolve(snapshot, Fixtures.controller_name()),
        snapshot
      )

      assert_receive {:applied, %{"kind" => "Deployment"} = deployment}
      [container] = deployment["spec"]["template"]["spec"]["containers"]
      assert Enum.map(container["ports"], & &1["containerPort"]) == [80, 8080]
      assert_receive {:applied, %{"kind" => "Service"}}
      refute_receive {:applied, _}, 50
      assert :sys.get_state(deployer).pending == %{}
    end

    test "an object no longer desired loses its retry", ctx do
      deployer = start_deployer(apply: %{"Deployment" => [{:error, :down}]})
      Deployer.reconcile(deployer, ctx.graph, ctx.snapshot)
      assert applied(4) == ["ConfigMap", "ServiceAccount", "Deployment", "Service"]

      Deployer.reconcile(deployer, Resolver.resolve(%{}, Fixtures.controller_name()), %{})
      refute_receive {:applied, _}, 50
      assert :sys.get_state(deployer).pending == %{}
    end

    test "a deleted Deployment or Service is applied again", ctx do
      deployer = start_deployer()
      Deployer.reconcile(deployer, ctx.graph, ctx.snapshot)
      assert applied(4) == ["ConfigMap", "ServiceAccount", "Deployment", "Service"]

      Deployer.reconcile(deployer, ctx.graph, ctx.live)
      refute_receive {:applied, _}, 50

      for {kind, gvk} <- [{"Deployment", Gvk.deployment()}, {"Service", Gvk.service()}] do
        Deployer.reconcile(deployer, ctx.graph, Map.delete(ctx.live, {gvk, "default", @name}))
        assert applied(1) == [kind]
        refute_receive {:applied, _}, 50
      end
    end

    test "a drifted owned field is repaired", ctx do
      deployer = start_deployer()
      Deployer.reconcile(deployer, ctx.graph, ctx.live)
      assert applied(4) == ["ConfigMap", "ServiceAccount", "Deployment", "Service"]

      key = {Gvk.deployment(), "default", @name}
      drifted = put_in(ctx.live, [key, "spec", "replicas"], 5)
      Deployer.reconcile(deployer, ctx.graph, drifted)
      assert applied(1) == ["Deployment"]
      refute_receive {:applied, _}, 50
    end

    test "fields only the server sets do not trigger an apply", ctx do
      deployer = start_deployer()
      Deployer.reconcile(deployer, ctx.graph, ctx.live)
      assert applied(4) == ["ConfigMap", "ServiceAccount", "Deployment", "Service"]

      key = {Gvk.service(), "default", @name}

      defaulted =
        ctx.live
        |> update_in([key], &Map.drop(&1, ["apiVersion", "kind"]))
        |> put_in([key, "metadata", "resourceVersion"], "42")
        |> put_in([key, "spec", "clusterIP"], "10.0.0.1")
        |> update_in([key, "spec", "ports"], fn ports ->
          Enum.map(ports, &Map.put(&1, "protocol", "TCP"))
        end)
        |> put_in([key, "status"], %{"loadBalancer" => %{"ingress" => [%{"ip" => "203.0.113.5"}]}})

      Deployer.reconcile(deployer, ctx.graph, defaulted)
      refute_receive {:applied, _}, 50
    end

    test "subset?/2 ignores extra live fields but not missing or differing ones" do
      assert Deployer.subset?(%{"a" => [%{"b" => 1}]}, %{"a" => [%{"b" => 1, "c" => 2}], "d" => 3})

      refute Deployer.subset?(%{"a" => [%{"b" => 1}]}, %{"a" => [%{"b" => 1}, %{"b" => 1}]})
      refute Deployer.subset?(%{"a" => %{"b" => 1}}, %{"a" => %{"b" => 2}})
      refute Deployer.subset?(%{"a" => 1}, %{})
    end

    test "ConfigMap and ServiceAccount are read and repaired on the verification tick", ctx do
      drifted =
        put_in(
          ctx.live[{{"", "v1", "ServiceAccount"}, "default", @name}],
          ["metadata", "labels"],
          %{}
        )

      reads = %{"ConfigMap" => [{:error, :not_found}], "ServiceAccount" => [{:ok, drifted}]}
      deployer = start_deployer(get: reads, verify_ms: 30)
      Deployer.reconcile(deployer, ctx.graph, ctx.live)
      assert applied(4) == ["ConfigMap", "ServiceAccount", "Deployment", "Service"]

      assert Enum.sort(applied(2)) == ["ConfigMap", "ServiceAccount"]
      refute_receive {:applied, _}, 50
      refute_received {:read, "Deployment"}
      refute_received {:read, "Service"}
    end

    test "a follower ignores reconciles", ctx do
      deployer = start_deployer(follower?: true)
      Deployer.reconcile(deployer, ctx.graph, ctx.snapshot)
      refute_receive {:applied, _}, 50
    end

    test "losing leadership cancels retries and stale retry timers are ignored", ctx do
      failures = [{:error, :down}, {:error, :down}]
      deployer = start_deployer(apply: %{"Deployment" => failures}, backoff_ms: 200)
      Deployer.reconcile(deployer, ctx.graph, ctx.snapshot)
      assert applied(4) == ["ConfigMap", "ServiceAccount", "Deployment", "Service"]

      Deployer.leadership(deployer, :lost)
      assert :sys.get_state(deployer).pending == %{}

      Deployer.leadership(deployer, :acquired)
      Deployer.reconcile(deployer, ctx.graph, ctx.snapshot)
      assert applied(4) == ["ConfigMap", "ServiceAccount", "Deployment", "Service"]

      send(deployer, {:retry, 1, @deployment_key})
      refute_receive {:applied, _}, 50

      send(deployer, {:retry, :sys.get_state(deployer).generation, @deployment_key})
      assert applied(1) == ["Deployment"]
    end

    test "backoff doubles from the initial delay and is capped at a minute" do
      assert Enum.map(1..7, &Deployer.backoff_ms/1) ==
               [1_000, 2_000, 4_000, 8_000, 16_000, 32_000, 60_000]

      assert Deployer.backoff_ms(100) == 60_000
      assert Deployer.backoff_ms(3, 10) == 40
    end
  end

  describe "Bootstrap.build/2" do
    test "points xds_cluster at the controller's ADS Service over HTTP/2" do
      [xds] = Bootstrap.build(gateway(), config())["static_resources"]["clusters"]

      assert xds["name"] == "xds_cluster"
      assert xds["type"] == "STRICT_DNS"

      endpoint =
        get_in(xds, [
          "load_assignment",
          "endpoints",
          Access.at(0),
          "lb_endpoints",
          Access.at(0),
          "endpoint",
          "address",
          "socket_address"
        ])

      assert endpoint["address"] == "arion-ctl-controller-ads.arion-system.svc.cluster.local"
      assert endpoint["port_value"] == 50051
    end
  end

  describe "Params.plan/2" do
    test "falls back to config defaults without parameters" do
      params = Params.plan(gateway(), config())

      assert params.image == "ghcr.io/arion-gateway/arion:0.1.0"
      assert params.replicas == 1
      assert params.service_type == "LoadBalancer"
      refute params.self_managed?
    end

    test "the Gateway's parameters override the defaults" do
      spec = %{"image" => "arion:custom", "replicas" => 4, "serviceType" => "ClusterIP"}
      params = Params.plan(%{gateway() | params: spec}, config())

      assert params.image == "arion:custom"
      assert params.replicas == 4
      assert params.service_type == "ClusterIP"
    end

    test "selfManaged opts the Gateway out of provisioning" do
      assert Params.plan(%{gateway() | params: %{"selfManaged" => true}}, config()).self_managed?
      assert Deployer.objects(%Ir.Graph{gateways: [gateway()]}, config()) |> length() == 4

      assert Deployer.objects(
               %Ir.Graph{gateways: [%{gateway() | params: %{"selfManaged" => true}}]},
               config()
             ) == []
    end

    test "a Gateway parametersRef selects its whole spec before the class's, from its namespace" do
      class_ref = %{
        "group" => "arion.io",
        "kind" => "ArionGatewayParameters",
        "name" => "class-params",
        "namespace" => "arion-system"
      }

      gateway_ref = %{
        "group" => "arion.io",
        "kind" => "ArionGatewayParameters",
        "name" => "gw-params"
      }

      objects = [
        Fixtures.gateway_class(params_ref: class_ref),
        Fixtures.gateway_params(
          name: "class-params",
          namespace: "arion-system",
          spec: %{"replicas" => 2, "serviceType" => "ClusterIP"}
        ),
        Fixtures.gateway_params(name: "gw-params", spec: %{"serviceType" => "NodePort"}),
        Fixtures.gateway(name: "inherits"),
        put_in(Fixtures.gateway(name: "own"), ["spec", "infrastructure"], %{
          "parametersRef" => gateway_ref
        })
      ]

      graph = objects |> Fixtures.snapshot() |> Resolver.resolve(Fixtures.controller_name())
      plans = Map.new(graph.gateways, &{&1.name, Params.plan(&1, config())})

      assert %{replicas: 2, service_type: "ClusterIP"} = plans["inherits"]
      # No field-by-field inheritance: the Gateway's spec leaves replicas to the default.
      assert %{replicas: 1, service_type: "NodePort"} = plans["own"]
    end
  end

  defp start_deployer(opts \\ []) do
    test = self()
    applies = start_supervised!({Agent, fn -> Keyword.get(opts, :apply, %{}) end}, id: :applies)
    reads = start_supervised!({Agent, fn -> Keyword.get(opts, :get, %{}) end}, id: :reads)
    config = %{config() | resync_interval_ms: Keyword.get(opts, :verify_ms, 60_000)}

    deployer =
      start_supervised!(
        {Deployer,
         config: config,
         initial_backoff_ms: Keyword.get(opts, :backoff_ms, 10),
         apply: fn object ->
           send(test, {:applied, object})
           scripted(applies, object["kind"], :ok)
         end,
         get: fn object ->
           send(test, {:read, object["kind"]})
           scripted(reads, object["kind"], {:ok, object})
         end}
      )

    unless opts[:follower?], do: Deployer.leadership(deployer, :acquired)
    deployer
  end

  defp scripted(agent, kind, default) do
    Agent.get_and_update(agent, fn results ->
      case results[kind] do
        [result | rest] -> {result, Map.put(results, kind, rest)}
        _ -> {default, results}
      end
    end)
  end

  defp applied(count) do
    for _ <- 1..count do
      assert_receive {:applied, object}, 500
      object["kind"]
    end
  end

  defp keys(kinds), do: for(kind <- kinds, do: {kind, "default", "gateway-default-demo"})

  # The snapshot with every desired object live, as the API server stored it.
  defp live(graph, snapshot) do
    graph
    |> Deployer.objects(config())
    |> Enum.map(&put_in(&1, ["metadata", "uid"], "live-uid"))
    |> Fixtures.snapshot()
    |> Map.merge(snapshot)
  end
end
