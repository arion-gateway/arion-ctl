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

defmodule Arion.ControlPlane.Helpers.Rbac do
  @moduledoc "RBAC rules as HTTP and network filters, with permissions and principals."

  alias Arion.ControlPlane.Helpers.Xds
  alias Arion.ControlPlane.Pb.Data.CidrRange
  alias Arion.ControlPlane.Pb.Data.Extensions, as: Ext

  def rules(action, policies \\ %{}), do: %Ext.RBAC{action: action, policies: policies}

  def policy(permissions, principals) when is_list(permissions) and is_list(principals),
    do: %Ext.Policy{permissions: permissions, principals: principals}

  def any_permission, do: %Ext.Permission{rule: {:any, true}}

  def any_principal, do: %Ext.Principal{identifier: {:any, true}}

  def destination_ip(address, prefix_len) do
    range = %CidrRange{address_prefix: address, prefix_len: Xds.uint32(prefix_len)}
    %Ext.Permission{rule: {:destination_ip, range}}
  end

  def header_permission(header_matcher), do: %Ext.Permission{rule: {:header, header_matcher}}

  def header_principal(header_matcher), do: %Ext.Principal{identifier: {:header, header_matcher}}

  def network_filter(name, rbac, stat_prefix \\ "network-rbac") do
    config = %Ext.RBACNetworkFilter{rules: rbac, stat_prefix: stat_prefix}
    Xds.network_filter(name, :rbac_network_filter, config)
  end

  def http_filter(name, rbac, rules_stat_prefix \\ "http-rbac") do
    config = %Ext.RBACConfig{rules: rbac, rules_stat_prefix: rules_stat_prefix}
    Xds.http_filter(name, :rbac_http_filter, config)
  end

  def per_route(rbac_config), do: %Ext.RBACPerRoute{rbac: rbac_config}
end
