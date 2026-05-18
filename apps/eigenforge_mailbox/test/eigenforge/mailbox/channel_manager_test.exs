defmodule Eigenforge.Mailbox.ChannelManagerTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Mailbox.ChannelManager
  alias Eigenforge.Mailbox.SignedProposalPublisher

  test "tracks subscribers and dispatches mailbox commands through the topic registry" do
    registry_name =
      Module.concat(__MODULE__, "Registry#{System.unique_integer([:positive])}")

    start_supervised!({Registry, keys: :duplicate, name: registry_name})

    topic = "commands:io"
    payload = %{"command_id" => "cmd-1"}
    parent = self()

    assert {:ok, _} = ChannelManager.subscribe(topic, registry_name: registry_name)

    child =
      spawn_link(fn ->
        {:ok, _} = ChannelManager.subscribe(topic, registry_name: registry_name)
        send(parent, :child_ready)

        receive do
          :stop -> :ok
        end
      end)

    assert_receive :child_ready, 1_000
    assert ChannelManager.subscriber_count(topic, registry_name: registry_name) == 2

    assert {:ok, 2} = ChannelManager.dispatch(topic, payload, registry_name: registry_name)

    send(child, :stop)
    Process.sleep(50)

    assert ChannelManager.subscriber_count(topic, registry_name: registry_name) == 1
  end

  test "dispatches signed proposals through the topic registry without altering the payload" do
    registry_name =
      Module.concat(__MODULE__, "ProposalRegistry#{System.unique_integer([:positive])}")

    start_supervised!({Registry, keys: :duplicate, name: registry_name})

    topic = "signed_proposals:io"

    proposal = %{
      "proposal_id" => "proposal-1",
      "signature" => "sig-1",
      "normalized_outcome" => "propose_action"
    }

    assert {:ok, _} = ChannelManager.subscribe(topic, registry_name: registry_name)
    assert :ok = SignedProposalPublisher.publish(topic, proposal, registry_name: registry_name)

    assert_receive {:mailbox_signed_proposal, ^topic, delivered}
    assert delivered == proposal
  end
end
