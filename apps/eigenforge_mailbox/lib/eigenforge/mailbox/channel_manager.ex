defmodule Eigenforge.Mailbox.ChannelManager do
  @moduledoc """
  Topic registration and dispatch boundary for mailbox traffic.
  """

  @default_registry Eigenforge.Mailbox.Registry

  @spec subscribe(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def subscribe(topic, opts \\ []) when is_binary(topic) do
    registry = Keyword.get(opts, :registry_name, @default_registry)
    Registry.register(registry, topic, [])
  end

  @spec dispatch(String.t(), map(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def dispatch(topic, payload, opts \\ []) when is_binary(topic) and is_map(payload) do
    registry = Keyword.get(opts, :registry_name, @default_registry)
    subscribers = Registry.lookup(registry, topic)

    Enum.each(subscribers, fn {pid, _value} ->
      send(pid, {:mailbox_command, topic, payload})
    end)

    {:ok, length(subscribers)}
  end

  @spec dispatch_signed_proposal(String.t(), map(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def dispatch_signed_proposal(topic, payload, opts \\ [])
      when is_binary(topic) and is_map(payload) do
    registry = Keyword.get(opts, :registry_name, @default_registry)
    subscribers = Registry.lookup(registry, topic)

    Enum.each(subscribers, fn {pid, _value} ->
      send(pid, {:mailbox_signed_proposal, topic, payload})
    end)

    {:ok, length(subscribers)}
  end

  @spec subscriber_count(String.t(), keyword()) :: non_neg_integer()
  def subscriber_count(topic, opts \\ []) when is_binary(topic) do
    registry = Keyword.get(opts, :registry_name, @default_registry)
    Registry.lookup(registry, topic) |> length()
  end
end
