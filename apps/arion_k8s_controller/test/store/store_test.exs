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

defmodule Arion.K8sController.StoreTest do
  use ExUnit.Case, async: true

  alias Arion.K8sController.{Fixtures, Store}
  alias Arion.K8sController.Kube.Gvk

  test "a store without kinds is synced" do
    assert Store.synced?(start_supervised!({Store, name: nil, engine: nil}))
  end

  test "a store is synced once every kind has been listed" do
    store =
      start_supervised!({Store, name: nil, engine: nil, kinds: [Gvk.gateway(), Gvk.service()]})

    Store.upsert(store, Gvk.gateway(), Fixtures.gateway())
    Store.upsert(store, Gvk.service(), Fixtures.service())
    refute Store.synced?(store)

    Store.replace_kind(store, Gvk.gateway(), [Fixtures.gateway()])
    refute Store.synced?(store)

    Store.replace_kind(store, Gvk.service(), [])
    assert Store.synced?(store)
  end

  test "upserting an identical object does not poke the engine; a changed object does" do
    store = start_supervised!({Store, name: nil, engine: self()})

    Store.upsert(store, Gvk.service(), Fixtures.service())
    assert_receive :dirty

    Store.upsert(store, Gvk.service(), Fixtures.service())
    refute_receive :dirty

    Store.upsert(store, Gvk.service(), Fixtures.service(port: 9090))
    assert_receive :dirty

    Store.delete(store, Gvk.service(), "default", "missing")
    refute_receive :dirty
  end

  test "listing a kind that is not required changes nothing" do
    store = start_supervised!({Store, name: nil, engine: nil, kinds: [Gvk.gateway()]})

    Store.replace_kind(store, Gvk.service(), [])
    refute Store.synced?(store)
  end
end
