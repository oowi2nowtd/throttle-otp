defmodule Throttle.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Throttle.Registry},
      {DynamicSupervisor, name: Throttle.BucketSupervisor, strategy: :one_for_one}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Throttle.Supervisor)
  end
end
