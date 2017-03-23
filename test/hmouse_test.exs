defmodule PlugHMouseTest do
  use ExUnit.Case
  use Plug.Test
  # doctest Hmouth

  @valid_options [secret_key: "MySecret-Key", header_key: "hmac-test"]
  @valid_hash_options @valid_options ++ [hash_algo: :sha256, digest: &Base.encode64/1]

  defmodule ErrorView do
    def hmouse_render("403.json") do
      %{"custom_error" => "This is a custom Error."}
    end

    def custom_strat(conn, response) do
      conn
      |> put_private(:custom_strat, "used")
      |> resp(403, Poison.encode!(response))
      |> send_resp()
    end
  end

  defp assert_unauthorized(conn) do
    assert conn.status == 403
    assert conn.halted
  end

  defp assert_authorized(conn) do
    assert conn.status != 403
    refute conn.halted
  end

  defp make_valid_request(%{content_type: content_type, body: body}) do
    hash = PlugHMouse.hash(body, @valid_hash_options)

    conn(:post, "/", body)
      |> put_req_header(@valid_options[:header_key], hash)
      |> put_req_header("content-type", content_type)
      |> PlugHMouse.call(PlugHMouse.init(@valid_options))
  end

  defp make_invalid_request(%{content_type: content_type, body: body, invalid_body: invalid_body}) do
    hash = PlugHMouse.hash(body, @valid_hash_options)

    conn(:post, "/", invalid_body)
      |> put_req_header(@valid_options[:header_key], hash)
      |> put_req_header("content-type", content_type)
      |> PlugHMouse.call(PlugHMouse.init(@valid_options))
  end

  @tag :urlencoded_invalid_request
  test "urlencoded request with invalid hmac" do
    %{content_type: "application/x-www-form-urlencoded", body: "The Body", invalid_body: "The invalid Body"}
    |> make_invalid_request()
    |> assert_unauthorized()
  end

  @tag :urlencoded_valid_request
  test "urlencoded request with valid hmac" do
    %{content_type: "application/x-www-form-urlencoded", body: "The Body"}
    |> make_valid_request()
    |> assert_authorized()
  end

  @tag :json_invalid_request
  test "JSON request with invalid hmac" do
    %{content_type: "application/vnd.api+json", body: Poison.encode!(%{"content" => "The Body"}), invalid_body: Poison.encode!(%{"content" => "The invalid Body"})}
    |> make_invalid_request()
    |> assert_unauthorized()
  end

  @tag :json_valid_request
  test "JSON request with valid hmac" do
    %{content_type: "application/vnd.api+json", body: Poison.encode!(%{"content" => "The Body"})}
    |> make_valid_request()
    |> assert_authorized()
  end

  @tag :config_error_views
  test "config error_views" do
    hash = PlugHMouse.hash(Poison.encode!(%{"content" => "The Body"}), @valid_hash_options)
    options = @valid_options ++ [error_views: [{"json", __MODULE__.ErrorView, "403.json", &__MODULE__.ErrorView.custom_strat/2}]]

    conn = conn(:post, "/", Poison.encode!(%{"content" => "The invalid Body"}))
      |> put_req_header(@valid_options[:header_key], hash)
      |> put_req_header("content-type", "application/vnd.api+json")
      |> PlugHMouse.call(PlugHMouse.init(options))

    assert conn.private.custom_strat == "used"
    assert conn.resp_body == Poison.encode!(__MODULE__.ErrorView.hmouse_render("403.json"))
  end

  @tag :hash
  test "hash/2" do
    hash = :crypto.hmac(:sha256, "AKey", "A String") |> Base.encode16

    assert hash == PlugHMouse.hash("A String", hash_algo: :sha256, secret_key: "AKey", digest: &Base.encode16/1)
  end

end
