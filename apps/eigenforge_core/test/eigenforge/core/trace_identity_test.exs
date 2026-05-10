defmodule Eigenforge.Core.TraceIdentityTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Core.TraceIdentity

  test "stable ids are deterministic" do
    assert TraceIdentity.stable_id("reasoner", ["snap-1", "propose_action", "on"]) ==
             TraceIdentity.stable_id("reasoner", ["snap-1", "propose_action", "on"])
  end

  test "source observation ids and receive ordering are deterministic" do
    assert TraceIdentity.source_observation_id("snap-1", "co2") ==
             TraceIdentity.source_observation_id("snap-1", "co2")

    assert TraceIdentity.receive_seq(3, "co2") == 3
    assert TraceIdentity.receive_monotonic_ms(7) == 7
  end
end
