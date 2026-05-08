#!/usr/bin/env elixir

snapshot =
  Eigenforge.Contracts.NormalizedSnapshot.new!(%{
    snapshot_id: "snap-1",
    snapshot_seq: 1,
    snapshot_hash: "hash-placeholder",
    room_id: "placeholder",
    co2_ppm: 1200,
    humidity_percent: 4500,
    temperature_c: 22000,
    fan_state: "off",
    source_entity_ids: %{
      "co2" => "sensor.placeholder_co2",
      "fan" => "switch.placeholder_fan"
    },
    source_observed_at: %{
      "co2" => "2026-05-08T11:40:00.000Z",
      "fan" => "2026-05-08T11:40:00.000Z"
    },
    normalized_at: "2026-05-08T11:40:00.000Z",
    freshness: "fresh"
  })

hash = Eigenforge.Contracts.NormalizedSnapshot.payload_hash(snapshot)
signature = Eigenforge.Contracts.NormalizedSnapshot.sign_hmac(snapshot, "test-secret")

unless byte_size(hash) == 64 do
  raise "expected SHA-256 payload hash to be 64 hex characters"
end

unless Eigenforge.Contracts.NormalizedSnapshot.verify_hmac(snapshot, "test-secret", signature) do
  raise "expected HMAC verification to pass"
end

IO.puts("contract smoke ok: #{snapshot.schema_id} hash=#{hash}")
