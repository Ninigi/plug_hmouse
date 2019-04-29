defmodule PlugHMouse do
  @moduledoc """
  An HMAC authentication plug.
  Replace Plug.Parsers with PlugHMouse and you are ready to go, for example:

      plug PlugHMouse,
        validate: {"MySecretKey123", "x-shopify-hmac-sha256"}

  ## Options

  * `:validate` - Tuple in the form of {"hmac-header-name", "MySecretKey"} or
    [{"hmac-header-name", "MySecretKey"}, {"another-hmac-header-name", "MyOtherSecretKey"}]. Keep
    in mind that Conn headers are **lowercase**, so if the original header is `X-Shopify-Hmac-SHA256`,
    the header key would be `"x-shopify-hmac-sha256"`

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
      Keyword.get(opts, :validate) || raise_missing_validate_opt()

      opts
    end

    defp raise_missing_validate_opt do
      raise ArgumentError, "PlugHMouse expects a :validate key"
    end
  end

  def init(opts) do
    opts
    |> Errors.raise_if_missing_key()
    |> parse_opts()
  end

  defp parse_opts(opts) do
    opts
    |> Keyword.put_new(:plug_parsers, @plug_parsers_default)
    |> Keyword.put_new(:error_views, @error_views_default)
  end

  def call(%Plug.Conn{req_headers: _} = conn, opts) do
    if conn.path_info |> must_be_validated?(List.keyfind(opts, :only, 0)) do
      opts = put_algo_opts(conn, opts)

      conn
      |> Plug.Parsers.call(Plug.Parsers.init(opts[:plug_parsers] ++ opts))
      |> get_hashes(opts[:validate], opts[:b16_digest], opts[:split_digest])
      |> compare_hashes()
      |> halt_or_pipe_through(opts)
    else
      conn |> Plug.Parsers.call(Plug.Parsers.init(opts[:plug_parsers] ++ opts))
    end
  end

  defp put_algo_opts(conn, opts) do
    do_put_algo_opts(opts, Keyword.get(opts, :validate), conn)
  end
  defp do_put_algo_opts(opts, {header_key, secret_key, hash_algo, digest}, _conn) do
    opts
    |> Keyword.put_new(:hash_algo, hash_algo)
    |> Keyword.put_new(:digest, digest)
    |> Keyword.put(:validate, {header_key, secret_key})
  end
  defp do_put_algo_opts(opts, {header_key, secret_key}, conn) do
    do_put_algo_opts(opts, {header_key, secret_key, :sha256, &Base.encode64/1}, conn)
  end
  defp do_put_algo_opts(opts, [validate_opt | rest], conn) do
    header_key = elem(validate_opt, 0)
    case List.keyfind(conn.req_headers, header_key, 0) do
      {^header_key, _} -> do_put_algo_opts(opts, validate_opt, conn)
      nil -> do_put_algo_opts(opts, rest, conn)
    end
  end
  defp do_put_algo_opts(opts, [validate_opt | []], conn) do
    header_key = elem(validate_opt, 0)
    case List.keyfind(conn.req_headers, header_key, 0) do
      {^header_key, _} -> do_put_algo_opts(opts, validate_opt, conn)
      nil -> do_put_algo_opts(opts, nil, nil)
    end
  end
  defp do_put_algo_opts(opts, _, _), do: opts

  defp must_be_validated?(_path_info, []), do: false
  defp must_be_validated?(_path_info, nil), do: true
  defp must_be_validated?(path_info, {:only, [validated_path]}) do
    is_path?(String.split(validated_path, "/"), path_info)
  end
  defp must_be_validated?(path_info, {:only, [validated_path | validated_paths]}) do
    is_path?(String.split(validated_path, "/"), path_info) || must_be_validated?(path_info, validated_paths)
  end

  defp is_path?(path_info, path_info), do: true
  defp is_path?([path_info_1], [path_info_1 | _]), do: true
  defp is_path?([":" <> _url_param], _), do: true
  defp is_path?([":" <> _url_param | rest_path_1], [_ | rest_path_2]), do: is_path?(rest_path_1, rest_path_2)
  defp is_path?(_, _), do: false

  defp get_hashes(conn, {header_key, secret_key}, b16 \\ false, split \\ false) do
    case List.keyfind(conn.req_headers, header_key, 0) do
      {^header_key, hash} ->
        {:ok, conn, get_hmouse_hash(conn), clean_hash(hash, b16, split)}
      nil ->
        {:ok, conn, get_hmouse_hash(conn), nil}
    end
  end

  defp clean_hash(hash, b16, true) do
    # in case of algo=digest format
    hash
    |> String.split("=")
    |> Enum.at(1)
    |> clean_hash(b16, false)
  end
  defp clean_hash(hash, true, _) do
    # in case hash comes as hex string
    case Base.decode16(hash, case: :mixed) do
      {:ok, bin_str} -> Base.encode64(bin_str)
      :error -> nil
    end
  end
  defp clean_hash(hash, _, _), do: hash

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
    :crypto.hmac(opts[:hash_algo], elem(opts[:validate], 1), string) |> opts[:digest].()
  end

  @spec put_plug_hmouse_hash(conn :: Plug.Conn.t, body :: String.t, opts :: Keyword.t) :: Plug.Conn.t
  def put_plug_hmouse_hash(conn, body, opts) do
    if conn.path_info |> must_be_validated?(List.keyfind(opts, :only, 0)) do
      put_private(conn, :plug_hmouse_hashed_body, PlugHMouse.hash(body, opts))
    else
      conn
    end
  end

end
