import Config

config :kvstore,
  virtual_nodes: 16,
  replication_factor: 2,
  sync_interval_ms: 60_000,
  http_port: 4001
