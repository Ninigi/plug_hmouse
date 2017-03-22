defmodule PlugHMouseTest do
  use ExUnit.Case
  use Plug.Test
  # doctest Hmouth

  defp assert_unauthorized(conn) do
    assert conn.status == 403
    assert conn.halted
  end

  defp assert_authorized(conn) do
    assert conn.status != 403
    refute conn.halted
  end

  defp valid_options do
    [secret_key: "MySecret-Key", header_key: "hmac-test"]
  end

  def valid_hash_options do
    valid_options() ++ [hash_algo: :sha256, digest: &Base.encode64/1]
  end

  @tag :urlencoded_invalid_request
  test "urlencoded request with invalid hmac" do
    body = "The Body"
    hash = PlugHMouse.hash(body, valid_hash_options())

    conn(:post, "/", body <> "Added Content")
      |> put_req_header(valid_options()[:header_key], hash)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> PlugHMouse.call(PlugHMouse.init(valid_options()))
      |> assert_unauthorized()
  end

  @tag :urlencoded_valid_request
  test "urlencoded request with valid hmac" do
    body = "The Body"
    hash = PlugHMouse.hash(body, valid_hash_options())

    conn(:post, "/", body)
      |> put_req_header(valid_options()[:header_key], hash)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> PlugHMouse.call(PlugHMouse.init(valid_options()))
      |> assert_authorized()
  end

  @tag :json_invalid_request
  test "JSON request with invalid hmac" do
    body = Poison.encode!(%{"content" => "The Body"})
    hash = PlugHMouse.hash(body, valid_hash_options())

    conn(:post, "/", Poison.encode!(%{"content" => "The Body - Added Content"}))
      |> put_req_header(valid_options()[:header_key], hash)
      |> put_req_header("content-type", "application/vnd.api+json")
      |> PlugHMouse.call(PlugHMouse.init(valid_options()))
      |> assert_unauthorized()
  end

  @tag :json_valid_request
  test "JSON request with valid hmac" do
    body = Poison.encode!(%{"content" => "The Body"})
    hash = PlugHMouse.hash(body, valid_hash_options())

    conn(:post, "/", body)
      |> put_req_header(valid_options()[:header_key], hash)
      |> put_req_header("content-type", "application/vnd.api+json")
      |> PlugHMouse.call(PlugHMouse.init(valid_options()))
      |> assert_authorized()
  end

  @tag :hash
  test "hash/2" do
    hash = :crypto.hmac(:sha256, "AKey", "A String") |> Base.encode16

    assert hash == PlugHMouse.hash("A String", hash_algo: :sha256, secret_key: "AKey", digest: &Base.encode16/1)
  end

end
