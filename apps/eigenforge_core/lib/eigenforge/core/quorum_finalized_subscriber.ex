defmodule Eigenforge.Core.QuorumFinalizedSubscriber do
  @moduledoc """
  Subscribes to IO quorum-finalized publications and persists them locally.
  """

  use GenServer

  alias Eigenforge.Core.LedgerSQLite
  alias Eigenforge.Core.LedgerWriter
  alias Eigenforge.Core.TraceIdentity
  alias Eigenforge.Mailbox.ChannelManager
  alias Eigenforge.Contracts
  require Logger

  @default_server __MODULE__
  @topic "quorum_finalized:io"

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {name, init_opts} = Keyword.pop(opts, :name, @default_server)

    case name do
      nil -> GenServer.start_link(__MODULE__, init_opts)
      _ -> GenServer.start_link(__MODULE__, init_opts, name: name)
    end
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, @default_server), start: {__MODULE__, :start_link, [opts]}}
  end

  @impl true
  def init(opts) do
    state = %{
      room_id: Keyword.fetch!(opts, :room_id),
      db_path: Keyword.fetch!(opts, :db_path),
      secret: Keyword.fetch!(opts, :secret),
      writer: Keyword.get(opts, :writer, LedgerWriter),
      mailbox_registry: Keyword.get(opts, :mailbox_registry, Eigenforge.Mailbox.Registry),
      seen_quorum_ids: MapSet.new()
    }

    case attempt_subscribe(state.mailbox_registry) do
      :ok ->
        {:ok, state}

      {:retry, delay_ms} ->
        Process.send_after(self(), :subscribe, delay_ms)
        {:ok, state}
    end
  end

  @impl true
  def handle_info(:subscribe, state) do
    case attempt_subscribe(state.mailbox_registry) do
      :ok -> {:noreply, state}
      {:retry, delay_ms} ->
        Process.send_after(self(), :subscribe, delay_ms)
        {:noreply, state}
    end
  end

  def handle_info({:mailbox_command, @topic, evidence}, state) when is_map(evidence) do
    next_state =
      if room_matches?(state, evidence) do
        case append_quorum_finalization(state, evidence) do
          :ok -> remember_quorum(state, evidence)
          {:duplicate, _reason} -> state
          {:conflict, reason} ->
            Logger.warning(
              "rejecting quorum_finalized repair evidence: #{inspect(reason)}"
            )

            state

          {:error, _reason} ->
            state
        end
      else
        state
      end

    {:noreply, next_state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp attempt_subscribe(registry_name) do
    case ChannelManager.subscribe(@topic, registry_name: registry_name) do
      {:ok, _} -> :ok
      {:error, _reason} -> {:retry, 500}
    end
  rescue
    _ -> {:retry, 500}
  end

  defp room_matches?(%{room_id: nil}, _evidence), do: true

  defp room_matches?(%{room_id: room_id}, evidence) do
    room_id == evidence["room_id"] || room_id == evidence[:room_id]
  end

  defp remember_quorum(state, evidence) do
    quorum_id = evidence["quorum_id"] || evidence[:quorum_id]
    %{state | seen_quorum_ids: MapSet.put(state.seen_quorum_ids, quorum_id)}
  end

  defp append_quorum_finalization(state, evidence) do
    with :ok <- reject_conflicting_finalization(state.db_path, evidence),
         {:ok, _event} <- LedgerWriter.append(state.writer, quorum_ledger_attrs(state, evidence)) do
      :ok
    else
      {:duplicate, reason} -> {:duplicate, reason}
      {:conflict, reason} -> {:conflict, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp reject_conflicting_finalization(db_path, evidence) do
    consensus_decision_id = evidence["consensus_decision_id"] || evidence[:consensus_decision_id]
    idempotency_key = evidence["idempotency_key"] || evidence[:idempotency_key]
    decision = evidence["decision"] || evidence[:decision]

    case LedgerSQLite.query_json(
           db_path,
           """
           SELECT consensus_decision_id, payload
           FROM ledger_events
           WHERE event_type = 'quorum_finalized'
           ORDER BY sequence ASC;
           """
         ) do
      {:ok, rows} ->
        case Enum.find_value(rows, :none, fn row ->
               payload = Contracts.decode_json!(row["payload"])
               existing_consensus_decision_id = row["consensus_decision_id"]
               existing_idempotency_key = payload["idempotency_key"]
               existing_decision = payload["decision"]

               cond do
                 existing_consensus_decision_id == consensus_decision_id and
                     existing_idempotency_key == idempotency_key and
                     existing_decision == decision ->
                   :duplicate

                 existing_consensus_decision_id == consensus_decision_id ->
                   {:conflict, {:consensus_decision_id, consensus_decision_id}}

                 existing_idempotency_key == idempotency_key ->
                   {:conflict, {:idempotency_key, idempotency_key}}

                 true ->
                   false
               end
             end) do
          :none -> :ok
          :duplicate -> {:duplicate, {:consensus_decision_id, consensus_decision_id}}
          {:conflict, reason} -> {:conflict, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp quorum_ledger_attrs(_state, evidence) do
    payload = quorum_payload(evidence)
    %{
      event_id: TraceIdentity.stable_id("quorum-finalized", [payload["quorum_id"]]),
      event_type: "quorum_finalized",
      consensus_decision_id: payload["consensus_decision_id"],
      consensus_status: "quorum_finalized",
      quorum_ref: quorum_ref(payload),
      causation_id: nil,
      correlation_id: TraceIdentity.stable_id("correlation", [payload["quorum_id"]]),
      subject: "core_rule_stub",
      source_app: "eigenforge_core",
      occurred_at: payload["published_at"],
      observed_at: payload["published_at"],
      payload: payload
    }
  end

  defp quorum_payload(evidence) do
    %{
      "room_id" => evidence["room_id"] || evidence[:room_id],
      "quorum_id" => evidence["quorum_id"] || evidence[:quorum_id],
      "consensus_decision_id" => evidence["consensus_decision_id"] || evidence[:consensus_decision_id],
      "idempotency_key" => evidence["idempotency_key"] || evidence[:idempotency_key],
      "target" => evidence["target"] || evidence[:target],
      "requested_state" => evidence["requested_state"] || evidence[:requested_state],
      "decision" => evidence["decision"] || evidence[:decision],
      "vote_count" => evidence["vote_count"] || evidence[:vote_count],
      "proposal_ids" => evidence["proposal_ids"] || evidence[:proposal_ids] || [],
      "core_node_ids" => evidence["core_node_ids"] || evidence[:core_node_ids] || [],
      "votes" => normalize_votes(evidence["votes"] || evidence[:votes] || []),
      "execution_status" =>
        evidence["execution_status"] || evidence[:execution_status] || "not_executed",
      "published_at" => evidence["published_at"] || evidence[:published_at]
    }
  end

  defp normalize_votes(votes) when is_list(votes) do
    Enum.map(votes, fn vote ->
      %{
        "proposal_id" => vote["proposal_id"] || vote[:proposal_id],
        "core_node_id" => vote["core_node_id"] || vote[:core_node_id],
        "consensus_decision_id" => vote["consensus_decision_id"] || vote[:consensus_decision_id],
        "idempotency_key" => vote["idempotency_key"] || vote[:idempotency_key],
        "normalized_outcome" => vote["normalized_outcome"] || vote[:normalized_outcome],
        "proposal_kind" => vote["proposal_kind"] || vote[:proposal_kind],
        "target" => vote["target"] || vote[:target],
        "requested_state" => vote["requested_state"] || vote[:requested_state]
      }
    end)
  end

  defp normalize_votes(_other), do: []

  defp quorum_ref(payload) do
    %{
      "quorum_id" => payload["quorum_id"],
      "decision" => payload["decision"],
      "proposal_ids" => payload["proposal_ids"],
      "core_node_ids" => payload["core_node_ids"],
      "vote_count" => payload["vote_count"],
      "execution_status" => payload["execution_status"]
    }
  end
end
