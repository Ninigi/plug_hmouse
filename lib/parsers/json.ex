defmodule PlugHMouse.Parsers.JSON do
  alias Plug.Conn
  import Plug.Parsers.JSON

  def parse(conn, "application", subtype, _headers, opts) do
    if subtype == "json" || String.ends_with?(subtype, "+json") do
      decoder = Keyword.get(opts, :json_decoder) ||
                  raise ArgumentError, "JSON parser expects a :json_decoder option"
      conn
      |> Conn.read_body(opts)
      |> decode(decoder, opts)
    else
      {:next, conn}
    end
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end

  defp decode({:more, _, conn}, _decoder, _opts) do
    {:error, :too_large, conn}
  end

  defp decode({:error, :timeout}, _decoder, _opts) do
    raise Plug.TimeoutError
  end

  defp decode({:error, _}, _decoder, _opts) do
    raise Plug.BadRequestError
  end

  defp decode({:ok, "", conn}, _decoder, opts) do
    {:ok, %{}, PlugHMouse.put_plug_hmouse_hash(conn, "", opts)}
  end

  defp decode({:ok, body, conn}, decoder, opts) do
    case decoder.decode!(body) do
      terms when is_map(terms) ->
        {:ok, terms, PlugHMouse.put_plug_hmouse_hash(conn, body, opts)}
      terms ->
        {:ok, %{"_json" => terms}, PlugHMouse.put_plug_hmouse_hash(conn, body, opts)}
    end
  rescue
    e -> raise Plug.Parsers.ParseError, exception: e
  end

end
