defmodule Eigenforge.MixTasks.LedgerTasksTest do
  use ExUnit.Case, async: false

  alias Eigenforge.Core.LedgerSQLite

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

    System.put_env("EIGENFORGE_IO_MODE", "simulator")
    System.put_env("EIGENFORGE_HMAC_SECRET", "ledger-task-secret")
    System.put_env("EIGENFORGE_CORE_NODE_ID", "core_a")
    System.put_env("EIGENFORGE_CORE_DB_PATH", db_path)
    Application.put_env(:eigenforge_core, :hmac_secret, "ledger-task-secret")

    on_exit(fn ->
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

    assert_raise Mix.Error, ~r/ledger verify failed/, fn ->
      Mix.Task.run("eigenforge.ledger.verify", [])
    end
  end

  test "ledger verify fails when a durable payload has the wrong schema version", %{db_path: db_path} do
    Mix.Task.reenable("eigenforge.ledger.genesis")
    Mix.Task.reenable("eigenforge.ledger.verify")

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

    assert_raise Mix.Error, ~r/ledger verify failed/, fn ->
      Mix.Task.run("eigenforge.ledger.verify", [])
    end
  end
end
