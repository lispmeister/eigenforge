defmodule Eigenforge.Mailbox.PubSubTransport do
  @moduledoc """
  PubSub-backed mailbox command transport for V1.
  """

  @behaviour Eigenforge.Mailbox.CommandTransport

  @impl true
  def publish_command(envelope, receipt, opts) when is_map(envelope) and is_map(receipt) do
    registry = Keyword.fetch!(opts, :registry_name)
    topic = Keyword.fetch!(opts, :topic)
    payload = %{"command" => envelope, "receipt" => receipt}

    delivered_to =
      Registry.dispatch(registry, topic, fn entries ->
        Enum.reduce(entries, 0, fn {pid, _value}, acc ->
          send(pid, {:mailbox_command, topic, payload})
          acc + 1
        end)
      end)

    {:ok, %{delivered_to: delivered_to, topic: topic}}
  end
end
