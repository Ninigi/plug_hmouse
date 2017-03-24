defmodule PlugHMouse do
  @moduledoc """
  An HMAC authentication plug.
  Replace Plug.Parsers with PlugHMouse and you are ready to go, for example:

      plug PlugHMouse,
        secret_key: "MySecretKey123",
        header_key: "x-shopify-hmac-sha256"

  ## Options

  * `:secret_key` - String used to sign a request body

  * `:header_key` - The signature-header's name. Keep in mind that Conn headers are **lowercase**,
    so if the original header is `X-Shopify-Hmac-SHA256`, the `:header_key` should be `"x-shopify-hmac-sha256"`

  * `:error_views` - Optional List of Tuples to define custom strategies to render a response when the
    verification fails. Values are in the Form of {"name-of-content-type",  MyApp.RenderStrategy, "template.name"}
    or {"name-of-content-type", MyApp.RenderStrategy, "template.name", MyApp.ResponseStrategy}

  * `:plug_parsers` - Optional List of options that will be passed to the Parsers, possible values are the
    Plug.Parsers options

  * `:hash_algo` - Optional hashing algorythm, defaults to `:sha256`. Possible values are:
    `[:md5, :sha, :sha224, :sha256, :sha384, :sha512]`

  * `:digest` - Optional digest function, defaults to `&Base.encode64/1`

  * `:only` - Optional List of paths to verify, it is easiest to use it like a namespace, for example:
    ... only: ["webhhooks/verified"]

  For more information about the awesomeness of Plug refer to https://github.com/elixir-lang/plug
  If you want to know more about the hashing implementation used in this library, go to http://erlang.org/doc/man/crypto.html#hmac-3
  """

  import Plug.Conn

  @plug_parsers_default [
    parsers: [PlugHMouse.Parsers.URLENCODED, :multipart, PlugHMouse.Parsers.JSON],
    pass: ["*/*"],
    json_decoder: Poison
  ]

  @error_views_default [
    {"json", PlugHMouse.RenderStrategy.JSONError, "403.json"},
    {"urlencoded", PlugHMouse.RenderStrategy.URLENCODEDError, "403"}
  ]

  defmodule Errors do
    @moduledoc false

    def raise_if_missing_key(opts) do
      Keyword.get(opts, :secret_key) || raise_missing_secret_key()
      Keyword.get(opts, :header_key) || raise_missing_header_key()

      opts
    end

    defp raise_missing_secret_key do
      raise ArgumentError, "PlugHMouse expects a secret_key"
    end

    defp raise_missing_header_key do
      raise ArgumentError, "PlugHMouse expects a header_key"
    end
  end

  def init(opts) do
    opts
    |> Errors.raise_if_missing_key()
    |> parse_opts()
  end

  defp parse_opts(opts) do
    opts
      |> Keyword.put_new(:hash_algo, :sha256)
      |> Keyword.put_new(:digest, &Base.encode64/1)
      |> Keyword.put_new(:plug_parsers, @plug_parsers_default)
      |> Keyword.put_new(:error_views, @error_views_default)
  end

  def call(%Plug.Conn{req_headers: _} = conn, opts) do
    do_call(conn, opts, List.keyfind(opts, :only, 0))
  end

  defp do_call(conn, opts) do
    conn
    |> Plug.Parsers.call(Plug.Parsers.init(opts[:plug_parsers] ++ opts))
    |> get_hashes(opts[:header_key])
    |> compare_hashes()
    |> halt_or_pipe_through(opts)
  end
  defp do_call(conn, opts, {:only, validated_paths}) do
    if conn.path_info |> must_be_validated?(validated_paths) do
      do_call(conn, opts)
    else
      conn
    end
  end
  defp do_call(conn, opts, nil), do: do_call(conn, opts)

  defp must_be_validated?(_path_info, []), do: false
  defp must_be_validated?(path_info, [validated_path]) do
    is_path?(String.split(validated_path, "/"), path_info)
  end
  defp must_be_validated?(path_info, [validated_path | validated_paths]) do
    is_path?(String.split(validated_path, "/"), path_info) || must_be_validated?(path_info, validated_paths)
  end

  defp is_path?(path_info, path_info), do: true
  defp is_path?([path_info_1], [path_info_1 | _]), do: true
  defp is_path?([":" <> _url_param], _), do: true
  defp is_path?([":" <> _url_param | rest_path_1], [_ | rest_path_2]), do: is_path?(rest_path_1, rest_path_2)
  defp is_path?(_, _), do: false

  defp get_hashes(conn, header_key) do
    case List.keyfind(conn.req_headers, header_key, 0) do
      {^header_key, hash} ->
        {:ok, conn, get_hmouse_hash(conn), hash}
      nil ->
        {:ok, conn, get_hmouse_hash(conn), nil}
    end
  end

  defp get_hmouse_hash(%{private: %{plug_hmouse_hashed_body: hash}}), do: hash
  defp get_hmouse_hash(_), do: "empty"

  defp compare_hashes({:ok, conn, hash, hash}), do: {:ok, conn}
  defp compare_hashes({:ok, conn, _, nil}), do: {:error, conn}
  defp compare_hashes({:ok, conn, _hash, _other_hash}), do: {:error, conn}

  defp halt_or_pipe_through({:ok, conn}, _),
    do: conn
  defp halt_or_pipe_through({:error, conn}, opts) do
    conn
    |> PlugHMouse.Render.render_error(opts[:error_views])
    |> halt()
  end

  @spec hash(string :: String.t, opts :: Keyword.t) :: String.t
  def hash(string, opts) do
    :crypto.hmac(opts[:hash_algo], opts[:secret_key], string) |> opts[:digest].()
  end

  @spec put_plug_hmouse_hash(conn :: Plug.Conn.t, body :: String.t, opts :: Keyword.t) :: Plug.Conn.t
  def put_plug_hmouse_hash(conn, body, opts) do
    put_private(conn, :plug_hmouse_hashed_body, PlugHMouse.hash(body, opts))
  end

end
