defmodule Eigenforge.Core.LedgerProjectionsTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.AfterActionEvent
  alias Eigenforge.Contracts.CommandEnvelope
  alias Eigenforge.Contracts.LedgerEvent
  alias Eigenforge.Contracts.NormalizedSnapshot
  alias Eigenforge.Contracts.PolicyDecision
  alias Eigenforge.Contracts.ReasonerOutcome
  alias Eigenforge.Core.LedgerProjections
  alias Eigenforge.Core.LedgerSQLite

  setup do
    db_path =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-projections-#{System.unique_integer([:positive])}.sqlite3"
      )

    on_exit(fn ->
      File.rm(db_path)
      File.rm("#{db_path}-wal")
      File.rm("#{db_path}-shm")
    end)

    assert :ok = LedgerSQLite.init(db_path, "core_a")
    assert :ok = insert_genesis(db_path)

    %{db_path: db_path}
  end

  test "creates projection tables and updates command lifecycle from ledger events", %{db_path: db_path} do
    assert :ok = LedgerProjections.init(db_path)

    events = decision_chain_events()

    Enum.each(events, fn event ->
      assert :ok = LedgerSQLite.append_event(db_path, event)
      assert :ok = LedgerProjections.apply_event(db_path, event)
    end)

    assert {:ok, [room]} =
             LedgerProjections.query_json(
               db_path,
               "SELECT * FROM latest_room_control_state WHERE room_id = 'placeholder';"
             )

    assert room["latest_snapshot_id"] == "snap-1"
    assert room["latest_snapshot_hash"] == String.duplicate("a", 64)
    assert room["latest_reasoner_outcome_id"] == "reasoner-1"
    assert room["latest_policy_decision_id"] == "policy-1"
    assert room["latest_command_id"] == "cmd-1"
    assert room["latest_after_action_id"] == "after-1"
    assert room["pending_command_id"] == nil
    assert room["pending_effect_key"] == nil
    assert room["command_lifecycle"] == "confirmed_changed"

    assert {:ok, [chain]} =
             LedgerProjections.query_json(
               db_path,
               "SELECT * FROM recent_control_chains WHERE correlation_id = 'corr-1';"
             )

    assert chain["room_id"] == "placeholder"
    assert chain["snapshot_id"] == "snap-1"
    assert chain["reasoner_outcome"] == "propose_action"
    assert chain["policy_decision"] == "allow"
    assert chain["command_id"] == "cmd-1"
    assert chain["effect_key"] == "effect-1"
    assert chain["after_action_status"] == "confirmed_changed"
  end

  test "rebuild reproduces the same ledger-derived projection state", %{db_path: db_path} do
    events = decision_chain_events()

    Enum.each(events, fn event ->
      assert :ok = LedgerSQLite.append_event(db_path, event)
      assert :ok = LedgerProjections.apply_event(db_path, event)
    end)

    assert {:ok, incremental_room} =
             LedgerProjections.query_json(
               db_path,
               "SELECT * FROM latest_room_control_state ORDER BY room_id ASC;"
             )

    assert {:ok, incremental_chain} =
             LedgerProjections.query_json(
               db_path,
               "SELECT * FROM recent_control_chains ORDER BY correlation_id ASC;"
             )

    assert :ok = LedgerProjections.rebuild(db_path)

    assert {:ok, rebuilt_room} =
             LedgerProjections.query_json(
               db_path,
               "SELECT * FROM latest_room_control_state ORDER BY room_id ASC;"
             )

    assert {:ok, rebuilt_chain} =
             LedgerProjections.query_json(
               db_path,
               "SELECT * FROM recent_control_chains ORDER BY correlation_id ASC;"
             )

    assert incremental_room == rebuilt_room
    assert incremental_chain == rebuilt_chain
  end

  test "observe_snapshot updates scaled sensor and freshness fields without touching ledger", %{
    db_path: db_path
  } do
    snapshot =
      NormalizedSnapshot.new!(%{
        snapshot_id: "snap-live",
        snapshot_seq: 7,
        snapshot_hash: String.duplicate("b", 64),
        room_id: "placeholder",
        co2_ppm: 1200,
        humidity_basis_points: 4500,
        temperature_millicelsius: 22_000,
        fan_state: "off",
        source_entity_ids: %{},
        source_observation_ids: %{},
        source_observed_at: %{},
        source_received_seq: %{},
        source_received_monotonic_ms: %{},
        source_status: %{
          "co2" => "fresh",
          "humidity" => "fresh",
          "temperature" => "fresh",
          "fan" => "not_yet_observed"
        },
        normalized_at: "2026-05-10T12:00:00.000Z",
        freshness: "fresh"
      })

    assert :ok = LedgerProjections.observe_snapshot(db_path, snapshot, io_mode: "simulator")

    assert {:ok, [room]} =
             LedgerProjections.query_json(
               db_path,
               "SELECT * FROM latest_room_control_state WHERE room_id = 'placeholder';"
             )

    assert room["co2_ppm"] == 1200
    assert room["humidity_basis_points"] == 4500
    assert room["temperature_millicelsius"] == 22000
    assert room["fan_state"] == "off"
    assert room["io_mode"] == "simulator"
    assert room["freshness"] == "fresh"
    assert room["fan_status"] == "not_yet_observed"

    assert {:ok, [%{"count(*)" => 1}]} =
             LedgerSQLite.query_json(db_path, "SELECT count(*) FROM ledger_events;")
  end

  defp decision_chain_events do
    [
      reasoner_event(),
      policy_event(),
      command_event(),
      after_action_event()
    ]
  end

  defp reasoner_event do
    payload =
      ReasonerOutcome.new!(%{
        reasoner_outcome_id: "reasoner-1",
        reasoner_id: "core_rule_stub",
        reasoner_version: "v1",
        snapshot_id: "snap-1",
        snapshot_hash: String.duplicate("a", 64),
        outcome_type: "propose_action",
        target: "actuator:fan",
        requested_state: "on",
        reason: "threshold exceeded",
        confidence_bps: 10000,
        metadata: %{}
      })
      |> Contracts.signable_map()

    ledger_event(2, "reasoner_outcome_recorded", payload)
  end

  defp policy_event do
    payload =
      PolicyDecision.new!(%{
        policy_decision_id: "policy-1",
        snapshot_id: "snap-1",
        snapshot_hash: String.duplicate("a", 64),
        reasoner_outcome_id: "reasoner-1",
        subject: "core_rule_stub",
        target: "actuator:fan",
        action: "command_actuator",
        scope: "room:placeholder",
        requested_state: "on",
        decision: "allow",
        capability_grant_id: "cap-1",
        capability_status: "allow",
        reason: "allowed",
        decided_at: "2026-05-10T12:00:01.000Z",
        metadata: %{}
      })
      |> Contracts.signable_map()

    ledger_event(3, "policy_decision_recorded", payload)
  end

  defp command_event do
    payload =
      CommandEnvelope.new!(%{
        command_id: "cmd-1",
        idempotency_key: "idem-1",
        effect_key: "effect-1",
        subject: "core_rule_stub",
        target: "actuator:fan",
        action: "command_actuator",
        scope: "room:placeholder",
        requested_state: "on",
        snapshot_id: "snap-1",
        snapshot_seq: 1,
        decision_event_id: "event-4",
        reasoner_outcome_event_id: "event-2",
        capability_event_id: "event-3",
        policy_decision_id: "policy-1",
        issued_at: "2026-05-10T12:00:02.000Z",
        expires_at: "2026-05-10T12:00:07.000Z",
        payload_hash: String.duplicate("c", 64),
        signature_version: "hmac-sha256-v1",
        signature: "sig-cmd"
      })
      |> Contracts.signable_map()

    ledger_event(4, "command_envelope_issued", payload)
  end

  defp after_action_event do
    payload =
      AfterActionEvent.new!(%{
        after_action_id: "after-1",
        command_id: "cmd-1",
        idempotency_key: "idem-1",
        effect_key: "effect-1",
        adapter_attempt_id: "attempt-1",
        target: "actuator:fan",
        requested_state: "on",
        observed_state: "on",
        status: "confirmed_changed",
        observed_at: "2026-05-10T12:00:03.000Z",
        reported_at: "2026-05-10T12:00:03.000Z",
        source_observation_ids: ["obs-1"],
        source_fault_event_ids: []
      })
      |> Contracts.signable_map()

    ledger_event(5, "after_action_recorded", payload)
  end

  defp ledger_event(sequence, event_type, payload) do
    LedgerEvent.new!(%{
      event_id: "event-#{sequence}",
      sequence: sequence,
      event_type: event_type,
      core_node_id: "core_a",
      consensus_decision_id: "consensus-1",
      consensus_status: "single_core_finalized",
      quorum_ref: %{},
      causation_id: if(sequence == 2, do: nil, else: "event-#{sequence - 1}"),
      correlation_id: "corr-1",
      subject: "core_rule_stub",
      source_app: "eigenforge_core",
      occurred_at: "2026-05-10T12:00:0#{sequence - 1}.000Z",
      observed_at: "2026-05-10T12:00:0#{sequence - 1}.000Z",
      persisted_at: "2026-05-10T12:00:0#{sequence - 1}.000Z",
      format_version: "json-canonical-v1",
      schema_id: "eigenforge.ledger_event",
      schema_version: 1,
      payload: payload,
      payload_hash: Contracts.hash_canonical(payload),
      previous_event_hash: if(sequence == 2, do: "hash-1", else: "hash-#{sequence - 1}"),
      event_hash: "hash-#{sequence}",
      signature_version: "hmac-sha256-v1",
      signature: "sig-#{sequence}"
    })
  end

  defp insert_genesis(db_path) do
    sql = """
    INSERT INTO ledger_events (
      sequence, event_id, event_type, core_node_id, consensus_decision_id,
      consensus_status, quorum_ref, causation_id, correlation_id, subject,
      source_app, occurred_at, observed_at, persisted_at, format_version,
      schema_id, schema_version, payload, payload_hash, previous_event_hash,
      event_hash, signature_version, signature
    ) VALUES (
      1,
      'event-1',
      'ledger_genesis',
      'core_a',
      NULL,
      NULL,
      '{}',
      NULL,
      'corr-1',
      'eigenforge_core',
      'eigenforge_core',
      '2026-05-10T12:00:00.000Z',
      '2026-05-10T12:00:00.000Z',
      '2026-05-10T12:00:00.000Z',
      'json-canonical-v1',
      'eigenforge.ledger_event',
      1,
      '{"kind":"ledger_genesis"}',
      '#{String.duplicate("a", 64)}',
      'eigenforge-ledger-genesis-v1',
      'hash-1',
      'hmac-sha256-v1',
      'sig-1'
    );
    """

    case LedgerSQLite.query(db_path, sql) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
