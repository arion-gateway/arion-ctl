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

defmodule Arion.K8sController.Reconcile.PrecedenceTest do
  use ExUnit.Case, async: true

  alias Arion.K8sController.Reconcile.Precedence

  defp c(match, opts \\ []) do
    %{
      match: match,
      namespace: Keyword.get(opts, :namespace, "default"),
      name: Keyword.get(opts, :name, "r"),
      creation_ts: Keyword.get(opts, :creation_ts, "2026-01-01T00:00:00Z")
    }
  end

  defp names_of(sorted), do: Enum.map(sorted, & &1.match["path"]["value"])

  test "exact beats longest prefix beats regex" do
    exact = c(%{"path" => %{"type" => "Exact", "value" => "/a"}})
    long = c(%{"path" => %{"type" => "PathPrefix", "value" => "/aaaa"}})
    short = c(%{"path" => %{"type" => "PathPrefix", "value" => "/a"}})
    regex = c(%{"path" => %{"type" => "RegularExpression", "value" => "/.*"}})

    assert names_of(Precedence.sort([regex, short, long, exact])) == ["/a", "/aaaa", "/a", "/.*"]
  end

  test "more header matches wins among equal paths" do
    plain = c(%{"path" => %{"type" => "PathPrefix", "value" => "/x"}}, name: "plain")

    with_headers =
      c(
        %{
          "path" => %{"type" => "PathPrefix", "value" => "/x"},
          "headers" => [%{"name" => "h", "value" => "v"}]
        },
        name: "hdr"
      )

    assert [%{name: "hdr"}, %{name: "plain"}] = Precedence.sort([plain, with_headers])
  end

  test "a method match wins over header and query param matches on an equal path" do
    path = %{"type" => "PathPrefix", "value" => "/"}
    method = c(%{"path" => path, "method" => "GET"}, name: "method")

    matchers =
      c(
        %{
          "path" => path,
          "headers" => [%{"name" => "h", "value" => "v"}],
          "queryParams" => [%{"name" => "q", "value" => "v"}]
        },
        name: "matchers"
      )

    assert [%{name: "method"}, %{name: "matchers"}] = Precedence.sort([matchers, method])
  end

  test "older route wins on a full tie" do
    old =
      c(%{"path" => %{"type" => "Exact", "value" => "/x"}},
        name: "old",
        creation_ts: "2026-01-01T00:00:00Z"
      )

    new =
      c(%{"path" => %{"type" => "Exact", "value" => "/x"}},
        name: "new",
        creation_ts: "2026-02-01T00:00:00Z"
      )

    assert [%{name: "old"}, %{name: "new"}] = Precedence.sort([new, old])
  end
end
