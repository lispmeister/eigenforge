defmodule Eigenforge.Core.LedgerSQLiteTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Contracts.LedgerEvent
  alias Eigenforge.Core.LedgerSQLite
  alias Eigenforge.Core.RuntimeConfig

  setup do
    db_path =
      Path.join(
        System.tmp_dir!(),
        "eigenforge-ledger-#{System.unique_integer([:positive])}.sqlite3"
      )

    on_exit(fn ->
      File.rm(db_path)
      File.rm("#{db_path}-wal")
      File.rm("#{db_path}-shm")
    end)

    %{db_path: db_path}
  end

  test "initializes the local sqlite ledger with WAL mode and append-only triggers", %{
    db_path: db_path
  } do
    config = %RuntimeConfig{core_db_path: db_path, core_node_id: "core_a"}

    assert :ok = LedgerSQLite.init(config)

    assert {:ok, journal_mode} = LedgerSQLite.query(db_path, "PRAGMA journal_mode;")
    assert String.trim(journal_mode) == "wal"

    assert {:ok, schema_sql} =
             LedgerSQLite.query(
               db_path,
               "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'ledger_events';"
             )

    assert schema_sql =~ "CREATE TABLE ledger_events"

    assert {:ok, triggers_sql} =
             LedgerSQLite.query(
               db_path,
               "SELECT group_concat(name, ',') FROM sqlite_master WHERE type = 'trigger' AND tbl_name = 'ledger_events';"
             )

    assert triggers_sql =~ "ledger_events_no_update"
    assert triggers_sql =~ "ledger_events_no_delete"
  end

  test "rejects invalid genesis rows and enforces append-only mutations", %{db_path: db_path} do
    assert :ok = LedgerSQLite.init(db_path, "core_a")

    invalid_genesis = sample_event(1, "reasoner_outcome_recorded")

    assert {:error, {:sqlite_query_failed, message}} =
             LedgerSQLite.append_event(db_path, invalid_genesis)

    assert message =~ "CHECK constraint failed"

    assert :ok = insert_genesis(db_path)

    assert {:error, {:sqlite_query_failed, update_message}} =
             LedgerSQLite.query(
               db_path,
               "UPDATE ledger_events SET subject = 'other' WHERE sequence = 1;"
             )

    assert update_message =~ "ledger_events is append-only"

    assert {:error, {:sqlite_query_failed, delete_message}} =
             LedgerSQLite.query(db_path, "DELETE FROM ledger_events WHERE sequence = 1;")

    assert delete_message =~ "ledger_events is append-only"
  end

  test "enforces uniqueness and decision-event consensus fields", %{db_path: db_path} do
    assert :ok = LedgerSQLite.init(db_path, "core_a")
    assert :ok = insert_genesis(db_path)
    assert :ok = LedgerSQLite.append_event(db_path, sample_event(2, "reasoner_outcome_recorded"))

    assert {:error, {:sqlite_query_failed, duplicate_message}} =
             LedgerSQLite.append_event(
               db_path,
               sample_event(3, "policy_decision_recorded", %{event_id: "event-2"})
             )

    assert duplicate_message =~ "UNIQUE constraint failed"

    assert {:error, {:sqlite_query_failed, consensus_message}} =
             LedgerSQLite.query(
               db_path,
               """
               INSERT INTO ledger_events (
                 sequence,
                 event_id,
                 event_type,
                 core_node_id,
                 consensus_decision_id,
                 consensus_status,
                 quorum_ref,
                 causation_id,
                 correlation_id,
                 subject,
                 source_app,
                 occurred_at,
                 observed_at,
                 persisted_at,
                 format_version,
                 schema_id,
                 schema_version,
                 payload,
                 payload_hash,
                 previous_event_hash,
                 event_hash,
                 signature_version,
                 signature
               ) VALUES (
                 4,
                 'event-4',
                 'policy_decision_recorded',
                 'core_a',
                 NULL,
                 NULL,
                 '{}',
                 NULL,
                 'correlation-4',
                 'core_rule_stub',
                 'eigenforge_core',
                 '2026-05-08T12:00:00.000Z',
                 '2026-05-08T12:00:00.000Z',
                 '2026-05-08T12:00:00.000Z',
                 'json-canonical-v1',
                 'eigenforge.ledger_event',
                 1,
                 '{"kind":"policy_decision_recorded"}',
                 '#{String.duplicate("b", 64)}',
                 'hash-2',
                 'hash-4',
                 'hmac-sha256-v1',
                 'sig-4'
               );
               """
             )

    assert consensus_message =~ "CHECK constraint failed"
  end

  defp sample_event(sequence, event_type, overrides \\ %{}) do
    base = %{
      event_id: "event-#{sequence}",
      sequence: sequence,
      event_type: event_type,
      core_node_id: "core_a",
      consensus_decision_id:
        if(event_type == "ledger_genesis", do: nil, else: "consensus-#{sequence}"),
      consensus_status: if(event_type == "ledger_genesis", do: nil, else: "single_core_finalized"),
      quorum_ref: %{},
      causation_id: nil,
      correlation_id: "correlation-#{sequence}",
      subject: "core_rule_stub",
      source_app: "eigenforge_core",
      occurred_at: "2026-05-08T12:00:00.000Z",
      observed_at: "2026-05-08T12:00:00.000Z",
      persisted_at: "2026-05-08T12:00:00.000Z",
      format_version: "json-canonical-v1",
      schema_id: "eigenforge.ledger_event",
      schema_version: 1,
      payload: %{"kind" => event_type, "ordinal" => sequence},
      payload_hash: String.duplicate("a", 64),
      previous_event_hash:
        if(sequence == 1, do: "eigenforge-ledger-genesis-v1", else: "prev-#{sequence - 1}"),
      event_hash: "hash-#{sequence}",
      signature_version: "hmac-sha256-v1",
      signature: "sig-#{sequence}"
    }

    base
    |> Map.merge(overrides)
    |> LedgerEvent.new!()
  end

  defp insert_genesis(db_path) do
    sql = """
    INSERT INTO ledger_events (
      sequence,
      event_id,
      event_type,
      core_node_id,
      consensus_decision_id,
      consensus_status,
      quorum_ref,
      causation_id,
      correlation_id,
      subject,
      source_app,
      occurred_at,
      observed_at,
      persisted_at,
      format_version,
      schema_id,
      schema_version,
      payload,
      payload_hash,
      previous_event_hash,
      event_hash,
      signature_version,
      signature
    ) VALUES (
      1,
      'event-1',
      'ledger_genesis',
      'core_a',
      NULL,
      NULL,
      '{}',
      NULL,
      'correlation-1',
      'core_rule_stub',
      'eigenforge_core',
      '2026-05-08T12:00:00.000Z',
      '2026-05-08T12:00:00.000Z',
      '2026-05-08T12:00:00.000Z',
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
