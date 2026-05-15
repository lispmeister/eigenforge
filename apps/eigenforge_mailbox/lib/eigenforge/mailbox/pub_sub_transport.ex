defmodule Eigenforge.Mailbox.PubSubTransport do
  @moduledoc """
  PubSub-backed mailbox command transport for V1.
  """

  @behaviour Eigenforge.Mailbox.CommandTransport

  alias Eigenforge.Mailbox.ChannelManager

  @impl true
  def publish_command(envelope, receipt, opts) when is_map(envelope) and is_map(receipt) do
    topic = Keyword.fetch!(opts, :topic)
    payload = %{"command" => envelope, "receipt" => receipt}

    with {:ok, delivered_to} <- ChannelManager.dispatch(topic, payload, opts) do
      {:ok, %{delivered_to: delivered_to, topic: topic}}
    end
  end
end
