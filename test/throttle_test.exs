defmodule ThrottleTest do
  use ExUnit.Case, async: true

  test "spends tokens up to capacity then refuses" do
    key = make_ref()

    for _ <- 1..3 do
      assert :ok = Throttle.check(key, capacity: 3)
    end

    assert {:error, :rate_limited, retry_after} = Throttle.check(key, capacity: 3)
    assert retry_after > 0
  end

  test "a refused call leaves the balance untouched" do
    key = make_ref()

    assert :ok = Throttle.check(key, capacity: 2)
    assert :ok = Throttle.check(key, capacity: 2)
    assert {:error, :rate_limited, _} = Throttle.check(key, capacity: 2)

    assert Throttle.tokens(key) == 0
  end

  test "refills one token per interval" do
    key = make_ref()

    assert :ok = Throttle.check(key, capacity: 1, refill_interval_ms: 50)
    assert {:error, :rate_limited, retry_after} = Throttle.check(key, capacity: 1, refill_interval_ms: 50)
    assert retry_after in 45..50

    Process.sleep(80)
    assert :ok = Throttle.check(key, capacity: 1, refill_interval_ms: 50)
  end

  test "cost larger than capacity never fits" do
    key = make_ref()
    assert {:error, :rate_limited, _} = Throttle.check(key, capacity: 1, cost: 5)
  end
end
