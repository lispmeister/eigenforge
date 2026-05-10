defmodule Eigenforge.MixTasks.SigningTasksTest do
  use ExUnit.Case, async: false

  alias Eigenforge.Contracts
  alias Eigenforge.Core.DetachedSignature

  setup do
    dir = Path.join(System.tmp_dir!(), "eigenforge-signing-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    on_exit(fn ->
      File.rm_rf(dir)
    end)

    original = Application.fetch_env!(:eigenforge_core, :hmac_secret)
    Application.put_env(:eigenforge_core, :hmac_secret, "task-secret")

    on_exit(fn ->
      Application.put_env(:eigenforge_core, :hmac_secret, original)
    end)

    %{dir: dir}
  end

  test "mix eigenforge.config.sign writes a detached sidecar for device inventory", %{dir: dir} do
    payload_path = Path.join(dir, "devices.json")
    sig_path = Path.join(dir, "devices.json.sig")

    File.write!(
      payload_path,
      Contracts.canonical_json(%{
        schema_id: "eigenforge.device_inventory",
        schema_version: 1,
        format_version: "json-canonical-v1",
        rooms: [%{room_id: "placeholder", active: true, sensors: [], actuators: []}]
      }) <> "\n"
    )

    Mix.Task.reenable("eigenforge.config.sign")

    Mix.Task.run("eigenforge.config.sign", ["--in", payload_path, "--sig", sig_path])

    payload = payload_path |> File.read!() |> Contracts.decode_json!()
    sidecar = sig_path |> File.read!() |> Contracts.decode_json!()

    assert sidecar["payload_hash"] == Contracts.hash_canonical(payload)

    expected_signature =
      Contracts.sign_hmac_excluding(
        sidecar,
        "task-secret",
        [:signature],
        "eigenforge:v1:config_sidecar"
      )

    assert sidecar["signature"] == expected_signature
  end

  test "mix eigenforge.capability.grant writes grant json and sidecar", %{dir: dir} do
    out_path = Path.join(dir, "grant.json")
    sig_path = Path.join(dir, "grant.json.sig")

    Mix.Task.reenable("eigenforge.capability.grant")

    Mix.Task.run("eigenforge.capability.grant", [
      "--subject",
      "core_rule_stub",
      "--target",
      "actuator:fan",
      "--action",
      "command_actuator",
      "--scope",
      "room:placeholder",
      "--out",
      out_path,
      "--sig",
      sig_path
    ])

    payload = out_path |> File.read!() |> Contracts.decode_json!()
    sidecar = sig_path |> File.read!() |> Contracts.decode_json!()

    assert payload["schema_id"] == "eigenforge.capability_grant"
    assert payload["grant_id"] == "cap-core-rule-stub-actuator-fan-command-actuator-room-placeholder"
    assert sidecar["signature_version"] == DetachedSignature.signature_version()

    expected_signature =
      Contracts.sign_hmac_excluding(
        sidecar,
        "task-secret",
        [:signature],
        "eigenforge:v1:capability_grant"
      )

    assert sidecar["payload_hash"] == Contracts.hash_canonical(payload)
    assert sidecar["signature"] == expected_signature
  end
end
