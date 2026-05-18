defmodule Eigenforge.MixTasks.LedgerTasksTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Eigenforge.Contracts
  alias Eigenforge.Core.LedgerSQLite
  alias Eigenforge.Core.LedgerWriter

  @repo_root Path.expand("../../../../..", __DIR__)

  setup do
    db_path =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-ledger-task-#{System.unique_integer([:positive])}.sqlite3"
      )

    original_env = %{
      "EIGENFORGE_IO_MODE" => System.get_env("EIGENFORGE_IO_MODE"),
      "EIGENFORGE_HMAC_SECRET" => System.get_env("EIGENFORGE_HMAC_SECRET"),
      "EIGENFORGE_CORE_NODE_ID" => System.get_env("EIGENFORGE_CORE_NODE_ID"),
      "EIGENFORGE_CORE_DB_PATH" => System.get_env("EIGENFORGE_CORE_DB_PATH")
    }

    original_secret = Application.fetch_env!(:eigenforge_core, :hmac_secret)

    System.put_env("EIGENFORGE_IO_MODE", "simulator")
    System.put_env("EIGENFORGE_HMAC_SECRET", "ledger-task-secret")
    System.put_env("EIGENFORGE_CORE_NODE_ID", "core_a")
    System.put_env("EIGENFORGE_CORE_DB_PATH", db_path)
    Application.put_env(:eigenforge_core, :hmac_secret, "ledger-task-secret")

    on_exit(fn ->
      Application.put_env(:eigenforge_core, :hmac_secret, original_secret)

      Enum.each(original_env, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)

      File.rm(db_path)
      File.rm("#{db_path}-wal")
      File.rm("#{db_path}-shm")
    end)

    %{db_path: db_path}
  end

  test "ledger genesis initializes a fresh database and verify passes", %{db_path: db_path} do
    Mix.Task.reenable("eigenforge.ledger.genesis")
    Mix.Task.reenable("eigenforge.ledger.verify")

    assert :ok = Mix.Task.run("eigenforge.ledger.genesis", [])
    assert :ok = Mix.Task.run("eigenforge.ledger.verify", [])

    assert {:ok, rows} =
             LedgerSQLite.query_json(db_path, "SELECT sequence, event_type FROM ledger_events;")

    assert rows == [%{"event_type" => "ledger_genesis", "sequence" => 1}]
  end

  test "ledger verify fails after manual row tampering", %{db_path: db_path} do
    Mix.Task.reenable("eigenforge.ledger.genesis")
    Mix.Task.reenable("eigenforge.ledger.verify")

    assert :ok = Mix.Task.run("eigenforge.ledger.genesis", [])

    assert {:ok, _} = LedgerSQLite.query(db_path, "DROP TRIGGER ledger_events_no_update;")

    assert {:ok, _} =
             LedgerSQLite.query(
               db_path,
               "UPDATE ledger_events SET event_hash = 'tampered-hash' WHERE sequence = 1;"
             )

    assert_raise Mix.Error, ~r/ledger verify failed:.*INV-11/, fn ->
      Mix.Task.run("eigenforge.ledger.verify", [])
    end
  end

  test "ledger verify fails when a durable payload has the wrong schema version", %{
    db_path: db_path
  } do
    Mix.Task.reenable("eigenforge.ledger.genesis")
    Mix.Task.reenable("eigenforge.ledger.verify")

    assert :ok = Mix.Task.run("eigenforge.ledger.genesis", [])
    assert {:ok, _} = LedgerSQLite.query(db_path, "DROP TRIGGER ledger_events_no_update;")

    secret = Application.fetch_env!(:eigenforge_core, :hmac_secret)

    {:ok, [%{"event_hash" => previous_event_hash}]} =
      LedgerSQLite.query_json(db_path, "SELECT event_hash FROM ledger_events WHERE sequence = 1;")

    payload = %{
      "format_version" => "json-canonical-v1",
      "schema_id" => "eigenforge.reasoner_outcome",
      "schema_version" => 2,
      "reasoner_outcome_id" => "outcome-1",
      "reasoner_id" => "core_rule_stub",
      "reasoner_version" => "v1",
      "snapshot_id" => "snap-1",
      "snapshot_hash" => String.duplicate("a", 64),
      "outcome_type" => "propose_action",
      "target" => "actuator:fan",
      "requested_state" => "on",
      "reason" => "test",
      "confidence_bps" => 10_000,
      "metadata" => %{}
    }

    base_row = %{
      "sequence" => 2,
      "event_id" => "event-2",
      "event_type" => "reasoner_outcome_recorded",
      "core_node_id" => "core_a",
      "consensus_decision_id" => "consensus-2",
      "consensus_status" => "single_core_finalized",
      "quorum_ref" => %{},
      "causation_id" => "event-1",
      "correlation_id" => "corr-2",
      "subject" => "core_rule_stub",
      "source_app" => "eigenforge_core",
      "occurred_at" => "2026-05-08T12:00:00.000Z",
      "observed_at" => "2026-05-08T12:00:00.000Z",
      "persisted_at" => "2026-05-08T12:00:00.000Z",
      "format_version" => "json-canonical-v1",
      "schema_id" => "eigenforge.ledger_event",
      "schema_version" => 1,
      "payload" => payload,
      "payload_hash" => Contracts.hash_canonical(payload),
      "previous_event_hash" => previous_event_hash,
      "event_hash" => "",
      "signature_version" => "hmac-sha256-v1",
      "signature" => ""
    }

    event_hash = Contracts.hash_excluding(base_row, [:event_hash, :signature])
    unsigned_row = Map.put(base_row, "event_hash", event_hash)

    signature =
      Contracts.sign_hmac_excluding(
        unsigned_row,
        secret,
        [:signature],
        "eigenforge:v1:ledger_event"
      )

    assert {:ok, _} =
             LedgerSQLite.query(
               db_path,
               """
               INSERT INTO ledger_events (
                 sequence, event_id, event_type, core_node_id, consensus_decision_id,
                 consensus_status, quorum_ref, causation_id, correlation_id, subject,
                 source_app, occurred_at, observed_at, persisted_at, format_version,
                 schema_id, schema_version, payload, payload_hash, previous_event_hash,
                 event_hash, signature_version, signature
               ) VALUES (
                 2,
                 'event-2',
                 'reasoner_outcome_recorded',
                 'core_a',
                 'consensus-2',
                 'single_core_finalized',
                 '{}',
                 'event-1',
                 'corr-2',
                 'core_rule_stub',
                 'eigenforge_core',
                 '2026-05-08T12:00:00.000Z',
                 '2026-05-08T12:00:00.000Z',
                 '2026-05-08T12:00:00.000Z',
                 'json-canonical-v1',
                 'eigenforge.ledger_event',
                 1,
                 '#{Contracts.canonical_json(payload)}',
                 '#{Contracts.hash_canonical(payload)}',
                 '#{previous_event_hash}',
                 '#{event_hash}',
                 'hmac-sha256-v1',
                 '#{signature}'
               );
               """
             )

    assert_raise Mix.Error, ~r/ledger verify failed:.*INV-10/, fn ->
      Mix.Task.run("eigenforge.ledger.verify", [])
    end
  end

  test "ledger verify warns on structurally valid quorum-finalized evidence", %{
    db_path: db_path
  } do
    Mix.Task.reenable("eigenforge.ledger.genesis")
    Mix.Task.reenable("eigenforge.ledger.verify")

    assert :ok = Mix.Task.run("eigenforge.ledger.genesis", [])
    assert {:ok, _} = LedgerSQLite.query(db_path, "DROP TRIGGER ledger_events_no_update;")

    assert {:ok, [%{"event_hash" => genesis_hash, "event_id" => genesis_event_id}]} =
             LedgerSQLite.query_json(
               db_path,
               "SELECT event_hash, event_id FROM ledger_events WHERE sequence = 1;"
             )

    fixture =
      @repo_root
      |> Path.join("test/golden_traces/v2_quorum_shape_compat.json")
      |> File.read!()
      |> Contracts.decode_json!()

    [event] = fixture["ledger_events"]
    assert {:ok, _} = insert_event(db_path, event, genesis_hash, genesis_event_id)

    log =
      capture_log(fn ->
        assert :ok = Mix.Task.run("eigenforge.ledger.verify", [])
      end)

    assert log =~ "INV-11 unsupported_consensus_status: quorum_finalized (V1 single-core only)"
  end

  test "ledger verify rejects unsupported consensus statuses on decision-chain rows", %{
    db_path: db_path
  } do
    Mix.Task.reenable("eigenforge.ledger.genesis")
    Mix.Task.reenable("eigenforge.ledger.verify")

    assert :ok = Mix.Task.run("eigenforge.ledger.genesis", [])
    assert {:ok, _} = LedgerSQLite.query(db_path, "DROP TRIGGER ledger_events_no_update;")

    assert {:ok, [%{"event_hash" => genesis_hash, "event_id" => genesis_event_id}]} =
             LedgerSQLite.query_json(
               db_path,
               "SELECT event_hash, event_id FROM ledger_events WHERE sequence = 1;"
             )

    event = %{
      "event_id" => "event-2",
      "sequence" => 2,
      "event_type" => "reasoner_outcome_recorded",
      "core_node_id" => "core_a",
      "consensus_decision_id" => "consensus-2",
      "consensus_status" => "bogus_status",
      "quorum_ref" => %{},
      "causation_id" => nil,
      "correlation_id" => "correlation-2",
      "subject" => "core_rule_stub",
      "source_app" => "eigenforge_core",
      "occurred_at" => "2026-05-08T12:00:00.000Z",
      "observed_at" => "2026-05-08T12:00:00.000Z",
      "persisted_at" => "2026-05-08T12:00:00.000Z",
      "format_version" => "json-canonical-v1",
      "schema_id" => "eigenforge.ledger_event",
      "schema_version" => 1,
      "payload" => %{
        "schema_id" => "eigenforge.reasoner_outcome",
        "schema_version" => 1,
        "format_version" => "json-canonical-v1",
        "reasoner_outcome_id" => "outcome-2",
        "reasoner_id" => "core_rule_stub",
        "reasoner_version" => "v1",
        "snapshot_id" => "snap-2",
        "snapshot_hash" => String.duplicate("a", 64),
        "outcome_type" => "propose_action",
        "target" => "actuator:fan",
        "requested_state" => "on",
        "reason" => "test",
        "confidence_bps" => 10_000,
        "metadata" => %{}
      },
      "payload_hash" => String.duplicate("b", 64),
      "previous_event_hash" => genesis_hash,
      "event_hash" => "hash-2",
      "signature_version" => "hmac-sha256-v1",
      "signature" => "sig-2"
    }

    assert {:ok, _} = insert_event(db_path, event, genesis_hash, genesis_event_id)

    assert_raise Mix.Error, ~r/ledger verify failed:.*INV-11.*unsupported_consensus_status/, fn ->
      Mix.Task.run("eigenforge.ledger.verify", [])
    end
  end

  test "ledger verify rejects duplicate finalized idempotency keys and conflicting decisions", %{
    db_path: db_path
  } do
    Mix.Task.reenable("eigenforge.ledger.verify")

    writer_name = Module.concat(__MODULE__, "Writer#{System.unique_integer([:positive])}")

    writer =
      start_supervised!(
        {LedgerWriter,
         db_path: db_path,
         core_node_id: "core_a",
         secret: "ledger-task-secret",
         name: writer_name}
      )

    assert {:ok, _} =
             LedgerWriter.append(writer,
               quorum_finalized_event(
                 "quorum-dup-1",
                 "consensus-dup-1",
                 "idem:v1:repair-dup",
                 "allow"
               )
             )

    assert {:ok, _} =
             LedgerWriter.append(writer,
               quorum_finalized_event(
                 "quorum-dup-2",
                 "consensus-dup-2",
                 "idem:v1:repair-dup",
                 "allow"
               )
             )

    assert_raise Mix.Error, ~r/ledger verify failed:.*INV-11.*duplicate_idempotency_key/, fn ->
      Mix.Task.run("eigenforge.ledger.verify", [])
    end
  end

  test "ledger verify rejects conflicting finalized decisions that reuse a consensus decision id", %{
    db_path: db_path
  } do
    Mix.Task.reenable("eigenforge.ledger.verify")

    writer_name = Module.concat(__MODULE__, "Writer#{System.unique_integer([:positive])}")

    writer =
      start_supervised!(
        {LedgerWriter,
         db_path: db_path,
         core_node_id: "core_a",
         secret: "ledger-task-secret",
         name: writer_name}
      )

    assert {:ok, _} =
             LedgerWriter.append(writer,
               quorum_finalized_event(
                 "quorum-conflict-1",
                 "consensus-conflict",
                 "idem:v1:repair-conflict-1",
                 "allow"
               )
             )

    assert {:ok, _} =
             LedgerWriter.append(writer,
               quorum_finalized_event(
                 "quorum-conflict-2",
                 "consensus-conflict",
                 "idem:v1:repair-conflict-2",
                 "deny"
               )
             )

    assert_raise Mix.Error, ~r/ledger verify failed:.*INV-11.*duplicate_finalized_decision/, fn ->
      Mix.Task.run("eigenforge.ledger.verify", [])
    end
  end

  test "ledger migrate validates a V1 ledger and rejects unsupported targets", %{
    db_path: _db_path
  } do
    Mix.Task.reenable("eigenforge.ledger.genesis")
    Mix.Task.reenable("eigenforge.ledger.migrate")

    assert :ok = Mix.Task.run("eigenforge.ledger.genesis", [])
    assert :ok = Mix.Task.run("eigenforge.ledger.migrate", ["--from", "1", "--to", "1"])

    Mix.Task.reenable("eigenforge.ledger.migrate")

    assert_raise Mix.Error, ~r/no V1→VN migration defined/, fn ->
      Mix.Task.run("eigenforge.ledger.migrate", ["--from", "1", "--to", "2"])
    end
  end

  test "ledger migrate fails when a payload is not schema version 1", %{db_path: db_path} do
    Mix.Task.reenable("eigenforge.ledger.genesis")
    Mix.Task.reenable("eigenforge.ledger.migrate")

    assert :ok = Mix.Task.run("eigenforge.ledger.genesis", [])
    assert {:ok, _} = LedgerSQLite.query(db_path, "DROP TRIGGER ledger_events_no_update;")

    assert {:ok, _} =
             LedgerSQLite.query(
               db_path,
               """
               INSERT INTO ledger_events (
                 sequence, event_id, event_type, core_node_id, consensus_decision_id,
                 consensus_status, quorum_ref, causation_id, correlation_id, subject,
                 source_app, occurred_at, observed_at, persisted_at, format_version,
                 schema_id, schema_version, payload, payload_hash, previous_event_hash,
                 event_hash, signature_version, signature
               ) VALUES (
                 2,
                 'event-2',
                 'reasoner_outcome_recorded',
                 'core_a',
                 'consensus-2',
                 'single_core_finalized',
                 '{}',
                 'event-1',
                 'corr-2',
                 'core_rule_stub',
                 'eigenforge_core',
                 '2026-05-08T12:00:00.000Z',
                 '2026-05-08T12:00:00.000Z',
                 '2026-05-08T12:00:00.000Z',
                 'json-canonical-v1',
                 'eigenforge.ledger_event',
                 1,
                 '{"schema_id":"eigenforge.reasoner_outcome","schema_version":2,"format_version":"json-canonical-v1","reasoner_outcome_id":"outcome-1","reasoner_id":"core_rule_stub","reasoner_version":"v1","snapshot_id":"snap-1","snapshot_hash":"#{String.duplicate("a", 64)}","outcome_type":"propose_action","target":"actuator:fan","requested_state":"on","reason":"test","confidence_bps":10000,"metadata":{}}',
                 '#{String.duplicate("b", 64)}',
                 'hash-1',
                 'hash-2',
                 'hmac-sha256-v1',
                 'sig-2'
               );
               """
             )

    assert_raise Mix.Error, ~r/ledger migrate failed: {:invalid_schema_version, 2, 2}/, fn ->
      Mix.Task.run("eigenforge.ledger.migrate", ["--from", "1", "--to", "1"])
    end
  end

  defp insert_event(db_path, event, genesis_hash, genesis_event_id) do
    payload_base = event["payload"]
    payload = payload_base |> Map.put("payload_hash", "") |> Map.put("signature", "")
    payload_hash = Contracts.hash_canonical(payload)
    payload_json = Contracts.canonical_json(payload)
    event_payload_hash = Contracts.hash_canonical(payload)

    event_unsigned = %{
      event
      | "payload" => payload,
        "payload_hash" => event_payload_hash,
        "previous_event_hash" => genesis_hash,
        "causation_id" => genesis_event_id
    }

    event_hash = Contracts.hash_excluding(event_unsigned, [:event_hash, :signature])

    signature =
      Contracts.sign_hmac_excluding(
        %{event_unsigned | "event_hash" => event_hash},
        Application.fetch_env!(:eigenforge_core, :hmac_secret),
        [:signature],
        "eigenforge:v1:ledger_event"
      )

    LedgerSQLite.query(
      db_path,
      """
      INSERT INTO ledger_events (
        sequence, event_id, event_type, core_node_id, consensus_decision_id,
        consensus_status, quorum_ref, causation_id, correlation_id, subject,
        source_app, occurred_at, observed_at, persisted_at, format_version,
        schema_id, schema_version, payload, payload_hash, previous_event_hash,
        event_hash, signature_version, signature
      ) VALUES (
        #{event["sequence"]},
        #{sql_string(event["event_id"])},
        #{sql_string(event["event_type"])},
        #{sql_string(event["core_node_id"])},
        #{sql_string(event["consensus_decision_id"])},
        #{sql_string(event["consensus_status"])},
        #{sql_string(Contracts.canonical_json(event["quorum_ref"]))},
        #{sql_value(genesis_event_id)},
        #{sql_string(event["correlation_id"])},
        #{sql_string(event["subject"])},
        #{sql_string(event["source_app"])},
        #{sql_string(event["occurred_at"])},
        #{sql_string(event["observed_at"])},
        #{sql_string(event["persisted_at"])},
        #{sql_string(event["format_version"])},
        #{sql_string(event["schema_id"])},
        #{event["schema_version"]},
        #{sql_string(payload_json)},
        #{sql_string(payload_hash)},
        #{sql_string(genesis_hash)},
        #{sql_string(event_hash)},
        #{sql_string(event["signature_version"])},
        #{sql_string(signature)}
      );
      """
    )
  end

  defp quorum_finalized_event(quorum_id, consensus_decision_id, idempotency_key, decision) do
    %{
      event_type: "quorum_finalized",
      consensus_decision_id: consensus_decision_id,
      consensus_status: "quorum_finalized",
      quorum_ref: %{
        "quorum_id" => quorum_id,
        "decision" => decision,
        "proposal_ids" => ["proposal-a", "proposal-b"],
        "core_node_ids" => ["core_a", "core_b"],
        "vote_count" => 2,
        "execution_status" => "executed"
      },
      payload: %{
        "format_version" => "json-canonical-v1",
        "schema_id" => "eigenforge.ledger_event",
        "schema_version" => 1,
        "kind" => "quorum_finalized",
        "room_id" => "placeholder",
        "quorum_id" => quorum_id,
        "consensus_decision_id" => consensus_decision_id,
        "idempotency_key" => idempotency_key,
        "target" => "actuator:fan",
        "requested_state" => if(decision == "allow", do: "on", else: nil),
        "decision" => decision,
        "vote_count" => 2,
        "proposal_ids" => ["proposal-a", "proposal-b"],
        "core_node_ids" => ["core_a", "core_b"],
        "votes" => [
          %{
            "proposal_id" => "#{quorum_id}-proposal-a",
            "core_node_id" => "core_a",
            "consensus_decision_id" => consensus_decision_id,
            "idempotency_key" => idempotency_key,
            "normalized_outcome" => if(decision == "allow", do: "propose_action", else: "propose_no_action"),
            "proposal_kind" => if(decision == "allow", do: "action", else: "no_action"),
            "target" => "actuator:fan",
            "requested_state" => if(decision == "allow", do: "on", else: nil)
          },
          %{
            "proposal_id" => "#{quorum_id}-proposal-b",
            "core_node_id" => "core_b",
            "consensus_decision_id" => consensus_decision_id,
            "idempotency_key" => idempotency_key,
            "normalized_outcome" => if(decision == "allow", do: "propose_action", else: "propose_no_action"),
            "proposal_kind" => if(decision == "allow", do: "action", else: "no_action"),
            "target" => "actuator:fan",
            "requested_state" => if(decision == "allow", do: "on", else: nil)
          }
        ],
        "execution_status" => "executed",
        "published_at" => "2026-05-08T12:00:00.000Z"
      }
    }
  end

  defp sql_value(nil), do: "NULL"
  defp sql_value(value), do: sql_string(value)

  defp sql_string(value), do: "'#{String.replace(to_string(value), "'", "''")}'"
end
