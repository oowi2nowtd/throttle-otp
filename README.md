# throttle-otp

Small token-bucket rate limiter for Elixir, one supervised process per key.

## Why

Rate limits usually live in front of something expensive: an upstream API with a
per-tenant quota, a login form, a webhook sender. A single ETS counter punishes
unrelated callers with one global lock and no way to report how long to wait.
Here every key owns a mailbox, so contention is scoped to the key that is
actually hot, and `check/2` tells the caller the wait instead of blocking.

## Usage

```elixir
# 5 requests per second per API token
case Throttle.check({:api, token}, capacity: 5, refill_interval_ms: 200) do
  :ok -> call_upstream(token)
  {:error, :rate_limited, wait_ms} -> {:retry, wait_ms}
end

Throttle.tokens({:api, token})  # current balance, or :absent
Throttle.reset({:api, token})   # drop the bucket and start over full
```

`cost:` charges more than one token per call. `refill_interval_ms: 0` makes a
fixed window that never refills; `retry_after_ms` is then `:infinity`.

## Supervision and failure semantics

`Throttle.Registry` (unique keys) and `Throttle.BucketSupervisor` (a
`DynamicSupervisor`) start under `Throttle.Supervisor` with `:one_for_one`.
Buckets are temporary children: the registry entry dies with the process, and
the next `check/2` starts a fresh bucket.

- A crashed bucket restarts full; limits are relaxed by at most one refill window.
- `Throttle.Sweeper` terminates buckets that sit full and untouched for five
  minutes (configurable via start options), so one-off keys do not leak processes. Deficit buckets
  are kept.
- All state is in memory. A VM restart resets every bucket.
- The first caller decides a key's options. Later callers with different
  options reuse the live bucket unchanged.
- Buckets never block: no queueing, no timeouts, `call` is bounded by the
  mailbox of one process.

## Install

No package release yet; use it from source:

```sh
git clone https://github.com/oowi2nowtd/throttle-otp
cd throttle-otp
mix test
```

Requires Elixir 1.16+ / OTP 26+. Drop it in as a path dependency or copy
`lib/` into your application and add it to your supervision tree.

## Layout

```
lib/throttle.ex              public API: check/2, tokens/1, reset/1
lib/throttle/bucket.ex       token bucket GenServer and refill arithmetic
lib/throttle/application.ex  registry, bucket supervisor, sweeper
lib/throttle/sweeper.ex      drops idle full buckets
test/throttle_test.exs       spend, refusal, refill, oversized cost
test/throttle/sweeper_test.exs  idle, deficit, and fresh bucket cases
```

## License

MIT, see `LICENSE`.
