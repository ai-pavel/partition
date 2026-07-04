import Config

config :kvstore,
  # Number of virtual nodes per physical node in the hash ring
  virtual_nodes: 128,
  # Replication factor: how many nodes store each key
  replication_factor: 3,
  # Anti-entropy sync interval in milliseconds
  sync_interval_ms: 5_000,
  # HTTP API port
  http_port: 4000

import_config "#{config_env()}.exs"
