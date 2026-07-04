defmodule KVStore.Application do
  @moduledoc """
  OTP Application for the distributed key-value store.

  Starts the hash ring, storage nodes, anti-entropy sync process,
  and HTTP API server.
  """
  use Application

  @impl true
  def start(_type, _args) do
    http_port = Application.get_env(:kvstore, :http_port, 4000)

    children = [
      # The consistent hash ring (must start before nodes)
      KVStore.Ring,
      # Dynamic supervisor for storage nodes
      {DynamicSupervisor, strategy: :one_for_one, name: KVStore.NodeSupervisor},
      # Node bootstrapper - starts initial local nodes
      {KVStore.NodeBootstrap, []},
      # Anti-entropy sync process
      KVStore.Sync,
      # HTTP API
      {Plug.Cowboy, scheme: :http, plug: KVStore.HTTP.Router, options: [port: http_port]}
    ]

    opts = [strategy: :one_for_one, name: KVStore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
