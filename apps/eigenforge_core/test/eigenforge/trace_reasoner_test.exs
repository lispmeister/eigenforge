defmodule Eigenforge.TraceReasonerTest do
  use ExUnit.Case, async: false

  alias Eigenforge.Trace

  defmodule StubReasoner do
    @behaviour Eigenforge.Core.Reasoner

    alias Eigenforge.Contracts.ReasonerOutcome

    @impl true
    def reason(snapshot) do
      {:ok,
       ReasonerOutcome.new!(%{
         reasoner_outcome_id: "stub-outcome-#{snapshot.snapshot_id}",
         reasoner_id: "stub_reasoner",
         reasoner_version: "test",
         snapshot_id: snapshot.snapshot_id,
         snapshot_hash: snapshot.snapshot_hash,
         outcome_type: "no_threshold_event",
         target: nil,
         requested_state: nil,
         reason: "stubbed",
         confidence_bps: 1234,
         metadata: %{"stub" => true}
       })}
    end
  end

  setup do
    previous = Application.get_env(:eigenforge_core, :reasoner_module)
    on_exit(fn -> Application.put_env(:eigenforge_core, :reasoner_module, previous) end)
    :ok
  end

  test "trace delegates to configured reasoner module" do
    Application.put_env(:eigenforge_core, :reasoner_module, StubReasoner)

    fixture = %{
      "snapshot_id" => "snap-stub",
      "snapshot_seq" => 1,
      "room_id" => "placeholder",
      "co2_ppm" => 1200,
      "humidity_basis_points" => 4500,
      "temperature_millicelsius" => 22_000,
      "fan_state" => "off",
      "source_entity_ids" => %{},
      "source_observation_ids" => %{},
      "source_observed_at" => %{},
      "source_received_seq" => %{},
      "source_received_monotonic_ms" => %{},
      "source_status" => %{},
      "normalized_at" => "2026-05-08T12:00:00.000Z",
      "freshness" => "fresh"
    }

    assert {:ok, trace} = Trace.run(fixture, "inline-fixture")

    assert [%{"payload" => payload}] =
             Enum.filter(trace["ledger_events"], &(&1["event_type"] == "reasoner_outcome_recorded"))

    assert payload["reasoner_id"] == "stub_reasoner"
    assert payload["reason"] == "stubbed"
  end
end
