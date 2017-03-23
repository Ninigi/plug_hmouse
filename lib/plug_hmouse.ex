defmodule PlugHMouse do
  import Plug.Conn

  @plug_parsers_default [
    parsers: [PlugHMouse.Parsers.URLENCODED, :multipart, PlugHMouse.Parsers.JSON],
    pass: ["*/*"],
    json_decoder: Poison
  ]

  @error_views_default [
    {"json", PlugHMouse.Render.JSONError, "403.json"},
    {"urlencoded", PlugHMouse.Render.URLENCODEDError, "403"}
  ]

  def init(opts) do
    opts
    |> raise_if_missing_key()
    |> parse_opts()
  end

  defp raise_if_missing_key(opts) do
    Keyword.get(opts, :secret_key) || raise_missing_secret_key
    Keyword.get(opts, :header_key) || raise_missing_header_key

    opts
  end

  defp raise_missing_secret_key do
    raise ArgumentError, "PlugHMouse expects a secret_key"
  end

  defp raise_missing_header_key do
    raise ArgumentError, "PlugHMouse expects a header_key"
  end

  defp parse_opts(opts) do
    opts
      |> Keyword.put_new(:hash_algo, :sha256)
      |> Keyword.put_new(:digest, &Base.encode64/1)
      |> Keyword.put_new(:plug_parsers, @plug_parsers_default)
      |> Keyword.put_new(:error_views, @error_views_default)
  end

  def call(%Plug.Conn{req_headers: req_headers} = conn, opts) do
    conn
    |> Plug.Parsers.call(Plug.Parsers.init(opts[:plug_parsers] ++ opts))
    |> get_hashes(opts[:header_key])
    |> compare_hashes()
    |> halt_or_pipe_through(opts)
  end

  defp get_hashes(conn, header_key) do
    case List.keyfind(conn.req_headers, header_key, 0) do
      {^header_key, hash} ->
        {:ok, conn, conn.private.plug_hmouse_hashed_body, hash}
      nil ->
        {:ok, conn, conn.private.plug_hmouse_hashed_body, nil}
    end
  end

  defp compare_hashes({:ok, conn, hash, hash}), do: {:ok, conn}
  defp compare_hashes({:ok, conn, _, nil}), do: {:ok, conn}
  defp compare_hashes({:ok, conn, _hash, _other_hash}), do: {:error, conn}

  defp halt_or_pipe_through({:ok, conn}, _),
    do: conn
  defp halt_or_pipe_through({:error, conn}, opts) do
    conn
    |> PlugHMouse.Render.render_error(opts[:error_views])
    |> halt()
  end

  def hash(string, opts) do
    :crypto.hmac(opts[:hash_algo], opts[:secret_key], string) |> opts[:digest].()
  end

  def put_plug_hmouse_hash(conn, body, opts) do
    put_private(conn, :plug_hmouse_hashed_body, PlugHMouse.hash(body, opts))
  end

end
