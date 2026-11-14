defmodule Throttle.Sweeper do
  @moduledoc """
  Periodically terminates buckets that have gone quiet while full.

  A bucket at full capacity is indistinguishable from a bucket that does not
  exist: the next call would refill it to exactly that state. So dropping a
  quiet, full bucket frees a process and a registry entry without changing any
  caller-visible decision.

  Buckets that still hold a deficit (`tokens < capacity`) are kept even when
  quiet, because their missing tokens are the actual limit state.

  A sweep between a lookup and its call can make `Throttle.check/2` create a
  fresh bucket on the first-caller-opts rule. That is the same outcome as a
  restart and is documented there.

  Tunables: `:interval_ms` (default 60_000) and `:ttl_ms` (default 300_000).
  """

  use GenServer
  require Logger

  @default_interval_ms 60_000
  @default_ttl_ms 300_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Runs one sweep, terminating every full bucket untouched for `ttl_ms`.

  Returns the number of terminated buckets. Exposed for tests and for hosts
  that want to drive sweeping from their own scheduler.
  """
  def sweep(ttl_ms) do
    now = System.monotonic_time(:millisecond)

    Throttle.Registry
    |> pids()
    |> Enum.count(&stale?(&1, now, ttl_ms))
  end

  defp pids(registry) do
    registry
    |> Registry.select([{{:_, :"$2", :_}, [], [:"$2"]}])
    |> Enum.uniq()
  end

  defp stale?(pid, now, ttl_ms) do
    state = :sys.get_state(pid)
    idle? = state.tokens >= state.capacity and now - state.updated_at >= ttl_ms

    idle? and terminate(pid)
  catch
    :exit, _ -> false
  end

  defp terminate(pid) do
    DynamicSupervisor.terminate_child(Throttle.BucketSupervisor, pid) == :ok
  end

  @impl true
  def init(opts) do
    state = %{
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      ttl_ms: Keyword.get(opts, :ttl_ms, @default_ttl_ms)
    }

    schedule(state.interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    case sweep(state.ttl_ms) do
      0 -> :ok
      swept -> Logger.debug("swept #{swept} idle throttle buckets")
    end

    schedule(state.interval_ms)
    {:noreply, state}
  end

  defp schedule(interval_ms), do: Process.send_after(self(), :sweep, interval_ms)
end
