defmodule ThrottleSweeperTest do
  use ExUnit.Case, async: false

  test "drops a full bucket that has been idle past the ttl" do
    key = make_ref()
    assert :ok = Throttle.check(key, capacity: 2)

    Throttle.Sweeper.sweep(0)
    assert Throttle.tokens(key) == :absent
  end

  test "keeps a bucket that still owes tokens" do
    key = make_ref()
    assert :ok = Throttle.check(key, capacity: 2, refill_interval_ms: 3_600_000)

    Throttle.Sweeper.sweep(0)
    assert Throttle.tokens(key) == 1
  end

  test "keeps a bucket touched within the ttl" do
    key = make_ref()
    assert :ok = Throttle.check(key, capacity: 1)

    Throttle.Sweeper.sweep(600_000)
    assert Throttle.tokens(key) == 0
  end
end
