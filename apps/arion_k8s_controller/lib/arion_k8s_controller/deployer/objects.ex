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

defmodule Arion.K8sController.Deployer.Objects do
  @moduledoc """
  Builds the Kubernetes objects for one provisioned Gateway data plane.

  Objects use deterministic names and Gateway ownerReferences so apply is
  convergent and Gateway deletion cascades.
  """

  alias Arion.K8sController.{Config, Ir}
  alias Arion.K8sController.Deployer.{Bootstrap, Params}
  alias Arion.K8sController.Kube.Gvk

  @field_manager "arion.io/k8s-controller"

  def field_manager, do: @field_manager

  def build(%Ir.Gateway{} = gateway, %Params{} = params, %Config{} = config) do
    name = Ir.Gateway.object_name(gateway)
    bootstrap = gateway |> Bootstrap.build(config) |> Jason.encode!()

    [
      config_map(gateway, name, params, bootstrap),
      service_account(gateway, name, params),
      deployment(gateway, name, params, bootstrap),
      service(gateway, name, params)
    ]
  end

  defp config_map(gateway, name, params, bootstrap) do
    %{
      "apiVersion" => "v1",
      "kind" => "ConfigMap",
      "metadata" => meta(gateway, name, params),
      "data" => %{"bootstrap.json" => bootstrap}
    }
  end

  defp service_account(gateway, name, params) do
    %{
      "apiVersion" => "v1",
      "kind" => "ServiceAccount",
      "metadata" => meta(gateway, name, params)
    }
  end

  defp deployment(gateway, name, params, bootstrap) do
    %{
      "apiVersion" => "apps/v1",
      "kind" => "Deployment",
      "metadata" => meta(gateway, name, params),
      "spec" => %{
        "replicas" => params.replicas,
        "selector" => %{"matchLabels" => selector(name)},
        "template" => %{
          "metadata" => %{
            "labels" => labels(gateway, name, params),
            # The proxy reads its bootstrap only at startup.
            "annotations" =>
              Map.put(params.annotations, "arion.io/bootstrap-sha256", sha256(bootstrap))
          },
          "spec" => %{
            "serviceAccountName" => name,
            "containers" => [container(gateway, params)],
            "volumes" => [
              %{"name" => "bootstrap", "configMap" => %{"name" => name}}
            ]
          }
        }
      }
    }
  end

  defp container(gateway, params) do
    base = %{
      "name" => "arion",
      "image" => params.image,
      "command" => ["/arion"],
      "args" => ["--with-envoy-bootstrap", "/etc/arion/bootstrap.json"],
      "ports" => container_ports(gateway),
      "volumeMounts" => [
        %{"name" => "bootstrap", "mountPath" => "/etc/arion", "readOnly" => true}
      ]
    }

    if params.resources, do: Map.put(base, "resources", params.resources), else: base
  end

  defp service(gateway, name, params) do
    %{
      "apiVersion" => "v1",
      "kind" => "Service",
      "metadata" => meta(gateway, name, params),
      "spec" => %{
        "type" => params.service_type,
        "selector" => selector(name),
        "ports" => service_ports(gateway)
      }
    }
  end

  defp meta(gateway, name, params) do
    base = %{
      "name" => name,
      "namespace" => gateway.namespace,
      "labels" => Map.merge(params.labels, gateway_name_label(gateway)),
      "ownerReferences" => [owner_ref(gateway)]
    }

    if params.annotations == %{}, do: base, else: Map.put(base, "annotations", params.annotations)
  end

  defp gateway_name_label(gateway) do
    %{"gateway.networking.k8s.io/gateway-name" => Ir.Gateway.name_label(gateway)}
  end

  # No blockOwnerDeletion: it needs gateways/finalizers RBAC under the
  # OwnerReferencesPermissionEnforcement admission plugin, and GC cascades anyway.
  defp owner_ref(gateway) do
    %{
      "apiVersion" => Gvk.api_version(Gvk.gateway()),
      "kind" => Gvk.kind(Gvk.gateway()),
      "name" => gateway.name,
      "uid" => gateway.uid,
      "controller" => true
    }
  end

  defp sha256(data), do: :sha256 |> :crypto.hash(data) |> Base.encode16(case: :lower)

  defp labels(gateway, name, params) do
    params.labels
    |> Map.merge(gateway_name_label(gateway))
    |> Map.merge(selector(name))
  end

  defp selector(name),
    do: %{"app.kubernetes.io/name" => "arion", "app.kubernetes.io/instance" => name}

  defp ports(gateway) do
    gateway.listeners
    |> Enum.map(& &1.port)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp container_ports(gateway) do
    for port <- ports(gateway), do: %{"name" => "port-#{port}", "containerPort" => port}
  end

  defp service_ports(gateway) do
    for port <- ports(gateway),
        do: %{"name" => "port-#{port}", "port" => port, "targetPort" => port}
  end
end
