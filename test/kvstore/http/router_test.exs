defmodule KVStore.HTTP.RouterTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias KVStore.HTTP.Router

  @opts Router.init([])

  defp call(conn) do
    Router.call(conn, @opts)
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  defp put_key(key, value) do
    conn(:put, "/kv/#{key}", Jason.encode!(%{"value" => value}))
    |> put_req_header("content-type", "application/json")
    |> call()
  end

  test "PUT with a valid value returns 200 and ok status" do
    key = "router_put_#{:erlang.unique_integer([:positive])}"
    conn = put_key(key, "hello")

    assert conn.status == 200
    body = json_body(conn)
    assert body["key"] == key
    assert body["status"] == "ok"
  end

  test "PUT with a missing value returns 400" do
    key = "router_missing_#{:erlang.unique_integer([:positive])}"

    conn =
      conn(:put, "/kv/#{key}", Jason.encode!(%{"not_value" => "x"}))
      |> put_req_header("content-type", "application/json")
      |> call()

    assert conn.status == 400
    assert json_body(conn)["error"] =~ "value"
  end

  test "GET returns 200 with the stored value for a present key" do
    key = "router_get_#{:erlang.unique_integer([:positive])}"
    put_key(key, "world")

    conn = conn(:get, "/kv/#{key}") |> call()

    assert conn.status == 200
    body = json_body(conn)
    assert body["key"] == key
    assert body["value"] == "world"
  end

  test "GET returns 404 for an absent key" do
    key = "router_absent_#{:erlang.unique_integer([:positive])}"

    conn = conn(:get, "/kv/#{key}") |> call()

    assert conn.status == 404
    assert json_body(conn)["error"] == "not_found"
  end

  test "DELETE removes a key; a subsequent GET returns 404" do
    key = "router_del_#{:erlang.unique_integer([:positive])}"
    put_key(key, "doomed")

    del_conn = conn(:delete, "/kv/#{key}") |> call()
    assert del_conn.status == 200
    assert json_body(del_conn)["status"] == "deleted"

    get_conn = conn(:get, "/kv/#{key}") |> call()
    assert get_conn.status == 404
  end

  test "/health returns 200 with the uniform service body" do
    conn = conn(:get, "/health") |> call()

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"
    assert json_body(conn) == %{"status" => "ok", "service" => "partition"}
  end

  test "/ring returns 200 with the node list shape" do
    conn = conn(:get, "/ring") |> call()

    assert conn.status == 200
    body = json_body(conn)
    assert is_list(body["nodes"])
    assert is_integer(body["total"])
  end

  test "unknown route returns the catch-all 404" do
    conn = conn(:get, "/does/not/exist") |> call()

    assert conn.status == 404
    assert json_body(conn)["error"] == "not_found"
  end
end
