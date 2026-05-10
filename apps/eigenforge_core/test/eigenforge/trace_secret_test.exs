defmodule Eigenforge.TraceSecretTest do
  use ExUnit.Case, async: false

  @repo_root Path.expand("../../../..", __DIR__)
  @fixture Path.join(@repo_root, "config/simulator_snapshots/co2_high_fan_off.json")

  test "trace runner signatures follow configured hmac secret" do
    original = Application.fetch_env!(:eigenforge_core, :hmac_secret)

    on_exit(fn ->
      Application.put_env(:eigenforge_core, :hmac_secret, original)
    end)

    Application.put_env(:eigenforge_core, :hmac_secret, "override-secret")
    assert {:ok, override_trace} = Eigenforge.Trace.run_file(@fixture)

    Application.put_env(:eigenforge_core, :hmac_secret, original)
    assert {:ok, default_trace} = Eigenforge.Trace.run_file(@fixture)

    refute override_trace["command_envelopes"] == default_trace["command_envelopes"]
    refute override_trace["delivery_receipts"] == default_trace["delivery_receipts"]
    refute override_trace["ledger_events"] == default_trace["ledger_events"]
  end
end
