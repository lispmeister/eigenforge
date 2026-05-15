defmodule Eigenforge.Mailbox.LedgerNotifier do
  @moduledoc """
  Lightweight notifications for committed ledger events.
  """

  alias Eigenforge.Mailbox.ChannelManager

  @default_registry Eigenforge.Mailbox.Registry
  @default_topic "ledger_events:committed"

  @spec subscribe(keyword()) :: {:ok, term()} | {:error, term()}
  def subscribe(opts \\ []) do
    ChannelManager.subscribe(Keyword.get(opts, :topic, @default_topic),
      registry_name: Keyword.get(opts, :registry_name, @default_registry)
    )
  end

  @spec publish(map(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def publish(%{} = event, opts \\ []) do
    payload = %{
      "event_id" => event.event_id || event["event_id"],
      "event_type" => event.event_type || event["event_type"],
      "core_node_id" => event.core_node_id || event["core_node_id"]
    }

    ChannelManager.dispatch(
      Keyword.get(opts, :topic, @default_topic),
      %{"notification" => payload},
      registry_name: Keyword.get(opts, :registry_name, @default_registry)
    )
  end
end
