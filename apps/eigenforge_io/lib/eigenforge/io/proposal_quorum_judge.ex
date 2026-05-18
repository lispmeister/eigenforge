defmodule Eigenforge.IO.ProposalQuorumJudge do
  @moduledoc """
  Pure 2-of-3 proposal quorum tracking for IO-as-judge mode.

  The judge keeps per-decision vote buckets, rejects malformed or duplicate
  proposals, and finalizes a decision once two matching votes arrive.
  """

  alias Eigenforge.Contracts
  alias Eigenforge.Contracts.SignedProposal
  alias Eigenforge.Core.TraceIdentity

  defstruct hmac_secret: nil,
            seen_proposal_ids: MapSet.new(),
            finalized_decisions: MapSet.new(),
            buckets: %{}

  @type decision :: :allow | :deny
  @type rejection_reason ::
          :invalid_signed_proposal
          | :invalid_vote_signature
          | :invalid_vote_shape
          | :duplicate_proposal
          | :mismatched_vote

  @type outcome ::
          {:pending, map()}
          | {:rejected, rejection_reason(), map()}
          | {:quorum, decision(), map()}
          | {:ignored, map()}

  @spec new(binary()) :: t()
  def new(hmac_secret) when is_binary(hmac_secret) do
    %__MODULE__{hmac_secret: hmac_secret}
  end

  @spec ingest(t(), map()) :: {:ok, t(), outcome()}
  def ingest(%__MODULE__{} = judge, proposal) when is_map(proposal) do
    case SignedProposal.new(proposal) do
      {:ok, signed_proposal} ->
        case validate_signature(signed_proposal, judge.hmac_secret) do
          :ok -> accept_signed_proposal(judge, signed_proposal)
          {:error, reason} -> {:ok, judge, {:rejected, reason, proposal_summary(signed_proposal)}}
        end

      {:error, _reason} ->
        {:ok, judge, {:rejected, :invalid_signed_proposal, proposal_summary(proposal)}}
    end
  end

  defp accept_signed_proposal(judge, proposal) do
    cond do
      MapSet.member?(judge.finalized_decisions, proposal.consensus_decision_id) ->
        {:ok, judge, {:ignored, proposal_summary(proposal)}}

      MapSet.member?(judge.seen_proposal_ids, proposal.proposal_id) ->
        {:ok, judge, {:rejected, :duplicate_proposal, proposal_summary(proposal)}}

      proposal_kind_matches?(proposal) == false ->
        {:ok, judge, {:rejected, :invalid_vote_shape, proposal_summary(proposal)}}

      true ->
        bucket = Map.get(judge.buckets, proposal.consensus_decision_id, new_bucket(proposal))

        cond do
          MapSet.member?(bucket.core_node_ids, proposal.core_node_id) ->
            {:ok, judge, {:rejected, :duplicate_proposal, proposal_summary(proposal)}}

          true ->
            case ensure_bucket_compatible(bucket, proposal) do
              :ok ->
                next_bucket = add_vote(bucket, proposal)
                next_judge = put_bucket(judge, next_bucket, proposal)

                case quorum_decision(next_bucket) do
                  nil ->
                    {:ok, next_judge, {:pending, proposal_summary(proposal)}}

                  decision ->
                    evidence = build_quorum_evidence(next_bucket, decision)

                    {:ok,
                     finalize_bucket(next_judge, proposal.consensus_decision_id),
                     {:quorum, decision, evidence}}
                end

              {:error, reason} ->
                {:ok, judge, {:rejected, reason, proposal_summary(proposal)}}
            end
        end
    end
  end

  defp validate_signature(proposal, secret) do
    if is_binary(proposal.signature) and proposal.signature != "" do
      if Contracts.verify_hmac(proposal, secret, proposal.signature, "eigenforge:v1:signed_proposal") do
        :ok
      else
        {:error, :invalid_vote_signature}
      end
    else
      {:error, :invalid_vote_signature}
    end
  end

  defp proposal_kind_matches?(%SignedProposal{
         proposal_kind: "action",
         normalized_outcome: "propose_action",
         action: "command_actuator",
         requested_state: requested_state
       })
       when is_binary(requested_state) and requested_state != "",
    do: true

  defp proposal_kind_matches?(%SignedProposal{
         proposal_kind: "no_action",
         normalized_outcome: "propose_no_action",
         action: "no_command",
         requested_state: requested_state
       })
       when requested_state in [nil, ""],
    do: true

  defp proposal_kind_matches?(_proposal), do: false

  defp ensure_bucket_compatible(bucket, proposal) do
    cond do
      bucket.target != proposal.target ->
        {:error, :mismatched_vote}

      bucket.idempotency_key != proposal.idempotency_key ->
        {:error, :mismatched_vote}

      is_binary(bucket.requested_state) and is_binary(proposal.requested_state) and
          bucket.requested_state != proposal.requested_state ->
        {:error, :mismatched_vote}

      bucket.snapshot_id != proposal.snapshot_id ->
        {:error, :mismatched_vote}

      bucket.snapshot_hash != proposal.snapshot_hash ->
        {:error, :mismatched_vote}

      bucket.subject != proposal.subject ->
        {:error, :mismatched_vote}

      bucket.scope != proposal.scope ->
        {:error, :mismatched_vote}

      true ->
        :ok
    end
  end

  defp new_bucket(proposal) do
    %{
      consensus_decision_id: proposal.consensus_decision_id,
      target: proposal.target,
      idempotency_key: proposal.idempotency_key,
      requested_state:
        if(is_binary(proposal.requested_state) and proposal.requested_state != "",
          do: proposal.requested_state,
          else: nil
        ),
      snapshot_id: proposal.snapshot_id,
      snapshot_hash: proposal.snapshot_hash,
      subject: proposal.subject,
      scope: proposal.scope,
      votes: %{},
      proposal_ids: MapSet.new(),
      core_node_ids: MapSet.new(),
      finalized?: false
    }
  end

  defp add_vote(bucket, proposal) do
    vote = proposal_summary(proposal)
    requested_state =
      cond do
        is_binary(bucket.requested_state) and bucket.requested_state != "" ->
          bucket.requested_state

        is_binary(proposal.requested_state) and proposal.requested_state != "" ->
          proposal.requested_state

        true ->
          nil
      end

    bucket
    |> Map.update!(:votes, &Map.put(&1, proposal.core_node_id, vote))
    |> Map.update!(:proposal_ids, &MapSet.put(&1, proposal.proposal_id))
    |> Map.update!(:core_node_ids, &MapSet.put(&1, proposal.core_node_id))
    |> Map.put(:requested_state, requested_state)
  end

  defp put_bucket(judge, bucket, proposal) do
    buckets = Map.put(judge.buckets, bucket.consensus_decision_id, bucket)

    %{
      judge
      | seen_proposal_ids: MapSet.put(judge.seen_proposal_ids, proposal.proposal_id),
        buckets: buckets
    }
  end

  defp finalize_bucket(judge, consensus_decision_id) do
    bucket = Map.fetch!(judge.buckets, consensus_decision_id)

    %{
      judge
      | finalized_decisions:
          MapSet.put(judge.finalized_decisions, consensus_decision_id),
        buckets: Map.put(judge.buckets, consensus_decision_id, %{bucket | finalized?: true})
    }
  end

  defp quorum_decision(%{votes: votes}) do
    counts =
      votes
      |> Map.values()
      |> Enum.map(& &1.normalized_outcome)
      |> Enum.frequencies()

    cond do
      Map.get(counts, "propose_action", 0) >= 2 -> :allow
      Map.get(counts, "propose_no_action", 0) >= 2 -> :deny
      true -> nil
    end
  end

  defp build_quorum_evidence(bucket, decision) do
    votes = bucket.votes |> Map.values() |> Enum.sort_by(& &1.core_node_id)

    %{
      quorum_id: TraceIdentity.stable_id("quorum", [bucket.consensus_decision_id]),
      consensus_decision_id: bucket.consensus_decision_id,
      idempotency_key: bucket.idempotency_key,
      target: bucket.target,
      requested_state: requested_state_for(bucket, decision),
      decision: decision,
      votes: votes,
      proposal_ids: Enum.map(votes, & &1.proposal_id),
      core_node_ids: Enum.map(votes, & &1.core_node_id),
      vote_count: length(votes),
      finalized_at: DateTime.utc_now() |> DateTime.truncate(:millisecond) |> DateTime.to_iso8601()
    }
  end

  defp requested_state_for(bucket, :allow) do
    bucket.requested_state
  end

  defp requested_state_for(_bucket, :deny), do: nil

  defp proposal_summary(%SignedProposal{} = proposal) do
    %{
      proposal_id: proposal.proposal_id,
      core_node_id: proposal.core_node_id,
      consensus_decision_id: proposal.consensus_decision_id,
      idempotency_key: proposal.idempotency_key,
      normalized_outcome: proposal.normalized_outcome,
      proposal_kind: proposal.proposal_kind,
      target: proposal.target,
      requested_state: proposal.requested_state
    }
  end

  defp proposal_summary(proposal) when is_map(proposal) do
    %{
      proposal_id: Map.get(proposal, "proposal_id") || Map.get(proposal, :proposal_id),
      core_node_id: Map.get(proposal, "core_node_id") || Map.get(proposal, :core_node_id),
      consensus_decision_id:
        Map.get(proposal, "consensus_decision_id") || Map.get(proposal, :consensus_decision_id),
      idempotency_key: Map.get(proposal, "idempotency_key") || Map.get(proposal, :idempotency_key),
      normalized_outcome:
        Map.get(proposal, "normalized_outcome") || Map.get(proposal, :normalized_outcome),
      proposal_kind: Map.get(proposal, "proposal_kind") || Map.get(proposal, :proposal_kind),
      target: Map.get(proposal, "target") || Map.get(proposal, :target),
      requested_state:
        Map.get(proposal, "requested_state") || Map.get(proposal, :requested_state)
    }
  end

  @type t :: %__MODULE__{
          hmac_secret: binary() | nil,
          seen_proposal_ids: MapSet.t(),
          finalized_decisions: MapSet.t(),
          buckets: map()
        }
end
