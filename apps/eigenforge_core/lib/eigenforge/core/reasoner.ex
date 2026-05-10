defmodule Eigenforge.Core.Reasoner do
  @moduledoc """
  Behaviour for V1 reasoner modules that derive a `ReasonerOutcome` from a
  normalized snapshot.
  """

  alias Eigenforge.Contracts.NormalizedSnapshot
  alias Eigenforge.Contracts.ReasonerOutcome

  @callback reason(NormalizedSnapshot.t()) :: {:ok, ReasonerOutcome.t()} | {:error, term()}
end
