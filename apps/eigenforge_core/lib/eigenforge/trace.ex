defmodule Eigenforge.Trace do
  @moduledoc """
  Deterministic simulator-backed trace runner for the V1 vertical slice.
  """

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.AfterActionEvent
  alias Eigenforge.Contracts.CapabilityCheck
  alias Eigenforge.Contracts.CommandEnvelope
  alias Eigenforge.Contracts.DeliveryReceipt
  alias Eigenforge.Contracts.LedgerEvent
  alias Eigenforge.Contracts.PolicyDecision
  alias Eigenforge.Contracts.ReasonerOutcome
  alias Eigenforge.Core.AfterActionObserver
  alias Eigenforge.Core.CapabilityChecker
  alias Eigenforge.Core.CanonicalTime
  alias Eigenforge.Core.CommandIssuer
  alias Eigenforge.Core.PolicyEngine
  alias Eigenforge.Core.Reasoner
  alias Eigenforge.Core.Reasoners.Co2Rules
  alias Eigenforge.Core.SimulatorFixture
  alias Eigenforge.Core.SnapshotBuilder
  alias Eigenforge.Core.TraceIdentity

  @subject "core_rule_stub"
  @signature_version "hmac-sha256-v1"
  @genesis_previous_hash "eigenforge-ledger-genesis-v1"
  @core_node_id "core_a"
  @ledger_backend "local_sqlite"
  @consensus_status "single_core_finalized"

  @type run_result :: {:ok, map()} | {:error, term()}

  @doc """
  Runs a deterministic trace from a normalized snapshot fixture path.
  """
  @spec run_file(Path.t()) :: run_result()
  def run_file(path) do
    with {:ok, body} <- File.read(path),
         {:ok, fixture} <- decode(body),
         {:ok, %{snapshot: snapshot}} <- SimulatorFixture.load(fixture),
         {:ok, trace} <- run(snapshot, fixture_display_path(path)) do
      {:ok, trace}
    end
  end

  @doc """
  Runs a deterministic trace from a fixture map.
  """
  @spec run(map(), Path.t() | nil) :: run_result()
  def run(fixture, fixture_path \\ nil) when is_map(fixture) do
    with {:ok, snapshot} <- build_snapshot(fixture),
         {:ok, reasoner} <- reason(snapshot),
         {:ok, capability} <- CapabilityChecker.check(reasoner, snapshot),
         {:ok, policy} <- PolicyEngine.decide(reasoner, capability, snapshot),
         {:ok, command} <- CommandIssuer.issue(reasoner, capability, policy, snapshot, secret()),
         {:ok, after_action} <- AfterActionObserver.observe(command) do

      payloads =
        [reasoner, capability, policy, command, after_action]
        |> Enum.reject(&is_nil/1)

      ledger_events = build_ledger(payloads, snapshot)
      delivery = maybe_delivery(command, ledger_events)

      trace =
        %{
          "trace_id" => stable_id("trace", [snapshot.snapshot_id]),
          "fixture" => fixture_path,
          "core_node_id" => @core_node_id,
          "ledger_backend" => @ledger_backend,
          "consensus_status" => @consensus_status,
          "steps" => steps(reasoner, capability, policy, command, delivery, after_action),
          "ledger_events" => Enum.map(ledger_events, &public_map/1),
          "command_envelopes" => maybe_list(command),
          "delivery_receipts" => maybe_list(delivery),
          "after_actions" => maybe_list(after_action),
          "verification" => verify_trace(ledger_events, command, delivery, after_action)
        }

      {:ok, trace}
    end
  end

  @doc """
  Verifies a trace JSON file produced by `run_file/1`.
  """
  @spec verify_file(Path.t()) :: :ok | {:error, term()}
  def verify_file(path) do
    with {:ok, body} <- File.read(path),
         {:ok, trace} <- decode(body) do
      verify_trace_file(path, trace)
    end
  end

  defp build_snapshot(fixture) do
    SnapshotBuilder.build(fixture)
  end

  defp fixture_display_path(path) do
    expanded = Path.expand(path)
    repo_root = Path.expand("../../../..", __DIR__)

    case Path.relative_to(expanded, repo_root) do
      ^expanded -> path
      relative -> relative
    end
  end

  defp reason(snapshot), do: reasoner_module().reason(snapshot)

  defp maybe_delivery(nil, _ledger_events), do: nil

  defp maybe_delivery(%CommandEnvelope{} = command, ledger_events) do
    command_event = Enum.find(ledger_events, &(&1.event_type == "command_envelope_issued"))

    base = %{
      receipt_id: stable_id("receipt", [command.command_id]),
      command_id: command.command_id,
      decision_event_id: command.decision_event_id,
      ledger_sequence: command_event.sequence,
      ledger_event_hash: command_event.event_hash,
      delivered_topic: "commands:io",
      delivered_at: timestamp(),
      signature_version: @signature_version,
      signature: ""
    }

    signature =
      Contracts.sign_hmac_excluding(
        base,
        secret(),
        [:signature],
        "eigenforge:v1:delivery_receipt"
      )
    DeliveryReceipt.new!(%{base | signature: signature})
  end

  defp build_ledger(payloads, snapshot) do
    consensus_decision_id = stable_id("consensus", [snapshot.snapshot_id])

    {events_reversed, _previous_hash, _sequence, _last_event_id} =
      Enum.reduce(payloads, {[], @genesis_previous_hash, 1, nil}, fn payload,
                                                                     {events, previous_hash, sequence, last_event_id} ->
        event_type = event_type(payload)
        event_id = stable_id("event", [event_type, snapshot.snapshot_id])
        payload_map = Contracts.signable_map(payload)

        base = %{
          event_id: event_id,
          sequence: sequence,
          event_type: event_type,
          core_node_id: @core_node_id,
          consensus_decision_id: consensus_decision_id,
          consensus_status: @consensus_status,
          quorum_ref: %{},
          causation_id: last_event_id,
          correlation_id: stable_id("correlation", [snapshot.snapshot_id]),
          subject: @subject,
          source_app: "eigenforge_core",
          occurred_at: timestamp(),
          observed_at: timestamp(),
          persisted_at: timestamp(),
          payload: payload_map,
          payload_hash: Contracts.hash_canonical(payload_map),
          previous_event_hash: previous_hash,
          event_hash: "",
          signature_version: @signature_version,
          signature: ""
        }

        event_hash = Contracts.hash_excluding(base, [:event_hash, :signature])
        unsigned = %{base | event_hash: event_hash}
        signature =
          Contracts.sign_hmac_excluding(
            unsigned,
            secret(),
            [:signature],
            "eigenforge:v1:ledger_event"
          )
        event = LedgerEvent.new!(%{unsigned | signature: signature})

        {[event | events], event.event_hash, sequence + 1, event.event_id}
      end)

    Enum.reverse(events_reversed)
  end

  defp event_type(%ReasonerOutcome{}), do: "reasoner_outcome_recorded"
  defp event_type(%CapabilityCheck{}), do: "capability_check_recorded"
  defp event_type(%PolicyDecision{decision: "deny_stale_snapshot"}), do: "stale_snapshot_denied"
  defp event_type(%PolicyDecision{}), do: "policy_decision_recorded"
  defp event_type(%CommandEnvelope{}), do: "command_envelope_issued"
  defp event_type(%AfterActionEvent{}), do: "after_action_recorded"

  defp verify_trace(ledger_events, command, delivery, after_action) do
    %{
      "ledger_hash_chain_valid" => ledger_hash_chain_valid?(ledger_events),
      "local_ledger_committed" => local_ledger_committed?(ledger_events),
      "consensus_status_valid" => consensus_status_valid?(ledger_events),
      "command_delivery_after_local_commit" =>
        is_nil(command) or Enum.any?(ledger_events, &(&1.event_type == "command_envelope_issued")),
      "delivery_receipt_valid" =>
        is_nil(delivery) or (not is_nil(command) and delivery.command_id == command.command_id),
      "after_action_core_authored" =>
        is_nil(after_action) or
          Enum.any?(ledger_events, &(&1.event_type == "after_action_recorded"))
    }
  end

  defp verify_trace_shape(%{
         "core_node_id" => @core_node_id,
         "ledger_backend" => @ledger_backend,
         "consensus_status" => @consensus_status,
         "ledger_events" => ledger_events,
         "verification" => verification
       })
       when is_list(ledger_events) and is_map(verification) do
    if Enum.all?(verification, fn {_key, value} -> value == true end) and
         trace_consensus_shape_valid?(ledger_events),
       do: :ok,
       else: {:error, {:verification_failed, verification}}
  end

  defp verify_trace_shape(_trace), do: {:error, :missing_verification}

  defp verify_trace_file(path, %{"fixture" => fixture_path} = trace) when is_binary(fixture_path) do
    with :ok <- verify_trace_shape(trace),
         {:ok, expected_trace} <- run_file(trace_fixture_path(path, fixture_path)) do
      expected_json = Contracts.canonical_json(expected_trace)
      actual_json = Contracts.canonical_json(trace)

      if actual_json == expected_json do
        :ok
      else
        {:error, :trace_mismatch}
      end
    end
  end

  defp verify_trace_file(_path, _trace), do: {:error, :missing_fixture}

  defp ledger_hash_chain_valid?([]), do: true

  defp ledger_hash_chain_valid?(events) do
    events
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [left, right] -> right.previous_event_hash == left.event_hash end)
  end

  defp local_ledger_committed?(events) do
    Enum.all?(events, &(&1.core_node_id == @core_node_id))
  end

  defp consensus_status_valid?(events) do
    Enum.all?(events, fn event ->
      event.consensus_status == @consensus_status and
        is_binary(event.consensus_decision_id) and
        event.consensus_decision_id != "" and
        event.quorum_ref == %{}
    end)
  end

  defp trace_consensus_shape_valid?(events) do
    consensus_ids =
      events
      |> Enum.map(&Map.get(&1, "consensus_decision_id"))
      |> Enum.uniq()

    match?([id] when is_binary(id) and id != "", consensus_ids) and
      Enum.all?(events, fn event ->
        Map.get(event, "core_node_id") == @core_node_id and
          Map.get(event, "consensus_status") == @consensus_status and
          Map.get(event, "quorum_ref") == %{}
      end)
  end

  defp steps(reasoner, capability, policy, command, delivery, after_action) do
    [
      %{"name" => "reasoner_outcome", "result" => reasoner.outcome_type},
      %{"name" => "capability_check", "result" => if(capability, do: capability.result, else: "not_checked")},
      %{"name" => "policy_decision", "result" => policy.decision},
      %{"name" => "finalized_decision", "result" => @consensus_status},
      %{"name" => "local_ledger_commit", "result" => "committed"},
      %{
        "name" => "command_envelope",
        "result" => if(command, do: "issued", else: "not_delivered")
      },
      %{
        "name" => "delivery_receipt",
        "result" => if(delivery, do: "issued", else: "not_applicable")
      },
      %{
        "name" => "after_action",
        "result" => if(after_action, do: after_action.status, else: "not_applicable")
      }
    ]
  end

  defp maybe_list(nil), do: []
  defp maybe_list(%_module{} = struct), do: [public_map(struct)]

  defp public_map(%_module{} = struct), do: struct |> Map.from_struct() |> public_map()

  defp public_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), public_map(value)} end)
  end

  defp public_map(list) when is_list(list), do: Enum.map(list, &public_map/1)
  defp public_map(value), do: value

  defp stable_id(prefix, parts) do
    TraceIdentity.stable_id(prefix, parts)
  end

  defp reasoner_module do
    module = Application.get_env(:eigenforge_core, :reasoner_module, Co2Rules)

    behaviours =
      if Code.ensure_loaded?(module) do
        module.module_info(:attributes)[:behaviour] || []
      else
        []
      end

    if function_exported?(module, :reason, 1) and Reasoner in behaviours do
      module
    else
      raise ArgumentError, "configured reasoner module must implement Eigenforge.Core.Reasoner"
    end
  end

  defp trace_fixture_path(trace_path, fixture_path) do
    if Path.type(fixture_path) == :absolute do
      fixture_path
    else
      derived_path =
        trace_path
        |> Path.dirname()
        |> Path.join("../../")
        |> Path.expand()
        |> Path.join(fixture_path)

      if File.exists?(derived_path), do: derived_path, else: Path.expand(fixture_path)
    end
  end

  defp secret do
    Application.fetch_env!(:eigenforge_core, :hmac_secret)
  end

  defp timestamp, do: CanonicalTime.trace_start()

  defp decode(body) do
    {:ok, Contracts.decode_json!(body)}
  rescue
    error -> {:error, {:invalid_json, Exception.message(error)}}
  end
end
