defmodule Throttle.Bucket do
  @moduledoc """
  A token bucket owned by one GenServer.

  State is monotonic: `updated_at` only ever moves forward, and tokens are
  refilled lazily on each call, so an idle bucket does no work between calls.

  Failure semantics: the bucket holds no durable state. If the process crashes
  and the DynamicSupervisor restarts it, the bucket comes back full. Callers
  that need a strict window should treat a restart as a reset rather than an
  error, which is why `acquire/2` never blocks and never retries.
  """

  use GenServer

  defstruct [:capacity, :refill_interval_ms, :tokens, :updated_at]

  def start_link({key, opts}) do
    GenServer.start_link(__MODULE__, opts, name: via(key))
  end

  def acquire(key, cost) do
    GenServer.call(via(key), {:acquire, cost, now_ms()})
  end

  defp via(key), do: {:via, Registry, {Throttle.Registry, key}}

  @impl true
  def init(opts) do
    capacity = Keyword.fetch!(opts, :capacity)

    state = %__MODULE__{
      capacity: capacity,
      refill_interval_ms: Keyword.get(opts, :refill_interval_ms, 1_000),
      tokens: capacity,
      updated_at: now_ms()
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:acquire, cost, now}, _from, state) do
    state = refill(state, now)

    if state.tokens >= cost do
      {:reply, :ok, %{state | tokens: state.tokens - cost}}
    else
      wait = retry_after(cost - state.tokens, state.refill_interval_ms)
      {:reply, {:error, :rate_limited, wait}, state}
    end
  end

  @impl true
  def handle_call(:tokens, _from, state) do
    state = refill(state, now_ms())
    {:reply, state.tokens, state}
  end

  defp refill(%{refill_interval_ms: 0} = state, now), do: %{state | updated_at: now}

  defp refill(state, now) do
    gained = div(now - state.updated_at, state.refill_interval_ms)

    if gained == 0 do
      state
    else
      %{
        state
        | tokens: min(state.capacity, state.tokens + gained),
          updated_at: state.updated_at + gained * state.refill_interval_ms
      }
    end
  end

  defp retry_after(_missing, 0), do: :infinity
  defp retry_after(missing, interval_ms), do: missing * interval_ms

  defp now_ms, do: System.monotonic_time(:millisecond)
end
