defmodule Throttle do
  @moduledoc """
  Per-key token-bucket rate limiting.

  Every key gets its own process supervised by `Throttle.BucketSupervisor`;
  the registry maps a key to that process, so concurrent callers for the same
  key serialize through one mailbox and cannot overspend a bucket.

  Buckets are created on first use. Creation options are taken from the first
  caller for a key; later callers that pass different options are ignored
  rather than re-configuring a live bucket.

  ## Failure semantics

    * `check/2` returns `:ok` or `{:error, :rate_limited, retry_after_ms}`
      where `retry_after_ms` may be `:infinity` for non-refilling buckets.
    * A bucket that crashes is restarted full by the supervisor.
    * The application has no dependency on a database; all state is in memory
      and is lost on VM restart.
  """

  @defaults [capacity: 10, refill_interval_ms: 1_000]

  @doc """
  Takes `cost` tokens from the bucket for `key`.

  Returns `:ok` when the tokens were available, otherwise
  `{:error, :rate_limited, retry_after_ms}` and leaves the bucket untouched.

  Options:

    * `:capacity` - maximum tokens (and the starting balance), default `10`
    * `:refill_interval_ms` - one token per interval; `0` disables refilling
  """
  @spec check(term(), keyword()) :: :ok | {:error, :rate_limited, non_neg_integer() | :infinity}
  def check(key, opts \\ []) do
    cost = Keyword.get(opts, :cost, 1)
    opts = Keyword.merge(@defaults, Keyword.take(opts, [:capacity, :refill_interval_ms]))

    with {:ok, pid} <- bucket_for(key, opts) do
      Throttle.Bucket.acquire(pid, cost)
    end
  end

  @doc """
  Current token balance for `key`, or `:absent` when no bucket exists yet.
  """
  def tokens(key) do
    case Registry.lookup(Throttle.Registry, key) do
      [{pid, _}] -> GenServer.call(pid, :tokens)
      [] -> :absent
    end
  end

  @doc "Stops the bucket for `key` if one exists."
  def reset(key) do
    case Registry.lookup(Throttle.Registry, key) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(Throttle.BucketSupervisor, pid)
      [] -> :ok
    end
  end

  defp bucket_for(key, opts) do
    case Registry.lookup(Throttle.Registry, key) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        case DynamicSupervisor.start_child(Throttle.BucketSupervisor, {Throttle.Bucket, {key, opts}}) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
        end
    end
  end
end
