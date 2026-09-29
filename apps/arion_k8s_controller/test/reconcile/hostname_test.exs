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

defmodule Arion.K8sController.Reconcile.Resolve.HostnameTest do
  use ExUnit.Case, async: true

  alias Arion.K8sController.Reconcile.Resolve.Hostname

  test "intersect/2 returns the narrower hostname of each match" do
    for {listener, routes, expected} <- [
          {"very.specific.com", ["non.matching.com", "*.specific.com"], ["very.specific.com"]},
          {"*.wildcard.io", ["wildcard.io", "foo.wildcard.io"], ["foo.wildcard.io"]},
          {"*.example.com", ["*.foo.example.com"], ["*.foo.example.com"]},
          {"*.foo.example.com", ["*.example.com"], ["*.foo.example.com"]},
          {"a.example.com", ["*.example.com", "a.example.com"], ["a.example.com"]},
          {"x.com", ["y.com"], :none},
          {nil, ["a.com", "*.b.com"], ["a.com", "*.b.com"]},
          {"a.com", [], ["a.com"]},
          {nil, [], ["*"]}
        ] do
      assert Hostname.intersect(listener, routes) == expected,
             "#{inspect(listener)} and #{inspect(routes)}"
    end
  end

  test "covers?/2 takes exact names and wildcard suffixes, not the suffix itself" do
    assert Hostname.covers?("a.example.com", "a.example.com")
    refute Hostname.covers?("a.example.com", "b.example.com")
    assert Hostname.covers?("*.example.com", "a.example.com")
    assert Hostname.covers?("*.example.com", "a.b.example.com")
    refute Hostname.covers?("*.example.com", "example.com")
    refute Hostname.covers?("*.example.com", "xexample.com")
    assert Hostname.covers?(nil, "anything.example")
    refute Hostname.covers?("a.example.com", "*.example.com")
    refute Hostname.covers?("*.example.com", nil)
    refute Hostname.covers?("a.example.com", nil)
  end

  test "overlap?/2 holds when either hostname covers the other" do
    assert Hostname.overlap?("*.example.com", "a.example.com")
    assert Hostname.overlap?("a.example.com", "*.example.com")
    assert Hostname.overlap?(nil, "a.example.com")
    assert Hostname.overlap?("*.example.com", nil)
    assert Hostname.overlap?("a.example.com", nil)
    refute Hostname.overlap?("a.example.com", "b.example.com")
    refute Hostname.overlap?("*.example.com", "*.example.net")
  end

  test "rank/1 orders exact names, then wildcards by specificity, then no hostname" do
    hosts = [nil, "*.example.com", "a.example.com", "*.sub.example.com"]

    assert Enum.sort_by(hosts, &Hostname.rank/1) ==
             ["a.example.com", "*.sub.example.com", "*.example.com", nil]
  end
end
