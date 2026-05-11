defmodule Eigenforge.IO.ActuatorStub do
  @moduledoc """
  V1 non-fan actuator stubs. These acknowledge supported placeholder targets
  without performing any physical IO.
  """

  @stub_targets MapSet.new(["actuator:light", "actuator:laser", "actuator:piezo_beeper"])

  @spec execute(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def execute(target, requested_state)
      when is_binary(target) and is_binary(requested_state) do
    if MapSet.member?(@stub_targets, target) do
      {:ok,
       %{
         "target" => target,
         "requested_state" => requested_state,
         "result" => "noop_stub",
         "physical_io_performed" => false
       }}
    else
      {:error, {:unsupported_target, target}}
    end
  end
end
