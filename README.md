# Distributed KV Store

An Elixir/OTP distributed key-value store using consistent hashing, CRDTs, and Merkle tree-based anti-entropy sync.

## Features

- **Consistent Hashing** with virtual nodes for key partitioning
- **CRDTs**: LWW-Register and G-Counter for conflict-free replication
- **Anti-entropy sync** via periodic Merkle tree comparison
- **HTTP API** via Plug

## API Endpoints

- `PUT /kv/:key` — store a value
- `GET /kv/:key` — retrieve a value
- `DELETE /kv/:key` — delete a key
- `GET /status` — cluster status

## Running

```bash
mix deps.get
mix compile
mix run --no-halt
```

## Testing

```bash
mix test
```
