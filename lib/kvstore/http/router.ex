defmodule KVStore.HTTP.Router do
  @moduledoc """
  Plug-based HTTP API for the key-value store.

  ## Endpoints

      PUT    /kv/:key   - Store a value (JSON body: {"value": ...})
      GET    /kv/:key   - Retrieve a value
      DELETE /kv/:key   - Delete a key
      GET    /health    - Health check
      GET    /ring      - Ring status (node list)
  """
  use Plug.Router

  plug(Plug.Logger)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

  # Health check
  get "/health" do
    json(conn, 200, Jason.OrderedObject.new(status: "ok", service: "distributed-kvstore"))
  end

  # Ring status
  get "/ring" do
    nodes = KVStore.Ring.nodes()

    json(conn, 200, %{
      nodes: Enum.map(nodes, &to_string/1),
      total: length(nodes)
    })
  end

  # Get a key
  get "/kv/:key" do
    case KVStore.get(key) do
      {:ok, value} ->
        json(conn, 200, %{key: key, value: value})

      {:error, :not_found} ->
        json(conn, 404, %{error: "not_found", key: key})
    end
  end

  # Put a key
  put "/kv/:key" do
    value = conn.body_params["value"]

    if is_nil(value) do
      json(conn, 400, %{error: "missing 'value' in request body"})
    else
      case KVStore.put(key, value) do
        :ok ->
          json(conn, 200, %{key: key, status: "ok"})

        {:error, reason} ->
          json(conn, 500, %{error: inspect(reason)})
      end
    end
  end

  # Delete a key
  delete "/kv/:key" do
    case KVStore.delete(key) do
      :ok ->
        json(conn, 200, %{key: key, status: "deleted"})

      {:error, reason} ->
        json(conn, 500, %{error: inspect(reason)})
    end
  end

  match _ do
    json(conn, 404, %{error: "not_found"})
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
