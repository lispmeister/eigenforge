defmodule Eigenforge.Core.PubSub do
  @moduledoc """
  Local topic registry for core snapshot and status wakeups.
  """

  @default_registry Eigenforge.Core.PubSub.Registry

  @spec publish(String.t(), term(), keyword()) :: :ok
  def publish(topic, message, opts \\ []) when is_binary(topic) do
    registry = Keyword.get(opts, :registry_name, @default_registry)

    Registry.dispatch(registry, topic, fn entries ->
      Enum.each(entries, fn {pid, _value} -> send(pid, {:core_pubsub, topic, message}) end)
    end)

    :ok
  end

  @spec subscribe(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def subscribe(topic, opts \\ []) when is_binary(topic) do
    registry = Keyword.get(opts, :registry_name, @default_registry)
    Registry.register(registry, topic, [])
  end
end
