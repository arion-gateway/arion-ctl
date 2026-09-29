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

defmodule Arion.K8sController.Reconcile.CertificateTest do
  use ExUnit.Case, async: true

  require Record

  alias Arion.K8sController.Reconcile.Certificate

  Record.defrecordp(
    :tbs_certificate,
    :TBSCertificate,
    Record.extract(:TBSCertificate, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  defp pair(key_spec, key_type) do
    %{cert: der, key: key} = :public_key.pkix_test_root_cert(~c"app", [{:key, key_spec}])
    cert_pem = :public_key.pem_encode([{:Certificate, der, :not_encrypted}])
    {cert_pem, :public_key.pem_encode([:public_key.pem_entry_encode(key_type, key)])}
  end

  defp data(cert_pem, key_pem),
    do: %{"tls.crt" => Base.encode64(cert_pem), "tls.key" => Base.encode64(key_pem)}

  test "RSA (PKCS#1), EC (SEC1) and PKCS#8 keys are re-encoded as PKCS#8" do
    for {key_spec, key_type} <- [
          {{:rsa, 2048, 65537}, :RSAPrivateKey},
          {{:rsa, 3072, 65537}, :PrivateKeyInfo},
          {{:namedCurve, :secp256r1}, :ECPrivateKey},
          {{:namedCurve, :secp384r1}, :PrivateKeyInfo},
          {{:namedCurve, :secp521r1}, :ECPrivateKey},
          {{:namedCurve, :ed25519}, :PrivateKeyInfo}
        ] do
      {cert_pem, key_pem} = pair(key_spec, key_type)

      assert {:ok, ^cert_pem, "-----BEGIN PRIVATE KEY-----" <> _ = pkcs8} =
               Certificate.parse(data(cert_pem, key_pem))

      assert [{:PrivateKeyInfo, _, :not_encrypted}] = :public_key.pem_decode(pkcs8)
    end
  end

  test "malformed, incomplete or mismatched data is rejected" do
    {cert_pem, key_pem} = pair({:namedCurve, :secp256r1}, :ECPrivateKey)
    {_other_cert, other_key} = pair({:namedCurve, :secp256r1}, :ECPrivateKey)
    corrupt = "-----BEGIN CERTIFICATE-----\n!!not base64**\n-----END CERTIFICATE-----\n"

    for data <- [
          # The conformance suite's malformed-certificate Secret.
          %{"tls.crt" => "SGVsbG8gd29ybGQK", "tls.key" => "SGVsbG8gd29ybGQK"},
          %{"tls.crt" => Base.encode64(cert_pem)},
          %{"tls.crt" => "not base64!", "tls.key" => Base.encode64(key_pem)},
          data(corrupt, key_pem),
          data(cert_pem, other_key),
          data(cert_pem, key_pem <> other_key)
        ] do
      assert Certificate.parse(data) == :error
    end
  end

  test "key types the proxy cannot load are rejected" do
    for key_spec <- [
          {:rsa, 1024, 65537},
          {:namedCurve, :secp224r1},
          {:namedCurve, :secp256k1},
          {:namedCurve, :brainpoolP256r1},
          {:namedCurve, :ed448}
        ] do
      {cert_pem, key_pem} = pair(key_spec, :PrivateKeyInfo)
      assert Certificate.parse(data(cert_pem, key_pem)) == :error
    end
  end

  test "a certificate with a malformed extension is rejected" do
    {cert_pem, key_pem} = pair({:namedCurve, :secp256r1}, :ECPrivateKey)
    [{:Certificate, der, :not_encrypted}] = :public_key.pem_decode(cert_pem)
    {:Certificate, tbs, algorithm, signature} = :public_key.der_decode(:Certificate, der)
    key_usage = {:Extension, {2, 5, 29, 15}, false, <<1, 2, 3>>}
    tbs = tbs_certificate(tbs, extensions: [key_usage])
    bad = :public_key.der_encode(:Certificate, {:Certificate, tbs, algorithm, signature})
    bad_pem = :public_key.pem_encode([{:Certificate, bad, :not_encrypted}])

    assert Certificate.parse(data(bad_pem, key_pem)) == :error
  end
end
