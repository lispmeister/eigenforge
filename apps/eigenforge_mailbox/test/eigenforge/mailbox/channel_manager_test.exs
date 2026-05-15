defmodule Eigenforge.Mailbox.ChannelManagerTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Mailbox.ChannelManager

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
end
