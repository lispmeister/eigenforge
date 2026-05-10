defmodule Eigenforge.Core.CanonicalTimeTest do
  use ExUnit.Case, async: true

  alias Eigenforge.Core.CanonicalTime

  test "accepts and formats canonical millisecond UTC timestamps" do
    assert {:ok, datetime} = CanonicalTime.parse("2026-05-10T12:34:56.789Z")
    assert CanonicalTime.format(datetime) == "2026-05-10T12:34:56.789Z"
  end

  test "rejects noncanonical timestamp shapes" do
    for timestamp <- [
          "2026-05-10T12:34:56Z",
          "2026-05-10T12:34:56.789+00:00",
          "2026-05-10T12:34:56.789123Z",
          "2026-5-10T12:34:56.789Z"
        ] do
      assert {:error, :noncanonical_timestamp} = CanonicalTime.parse(timestamp)
    end
  end

  test "adds milliseconds for persisted UTC deadlines" do
    assert CanonicalTime.add_ms("2026-05-08T12:00:00.000Z", 5000) ==
             "2026-05-08T12:00:05.000Z"
  end
end
