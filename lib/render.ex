defmodule PlugHMouse.Render do
  import Plug.Conn

  def urlencoded_strategy(conn, response) do
    conn
    |> put_resp_content_type("text/plain")
    |> resp(403, response)
    |> send_resp()
  end

  def json_strategy(conn, response) do
    conn
    |> put_resp_content_type("application/vnd.api+json")
    |> resp(403, Poison.encode!(response))
    |> send_resp()
  end

  @default_strategies %{
    "urlencoded" => &__MODULE__.urlencoded_strategy/2,
    "json" => &__MODULE__.json_strategy/2
  }

  def render_error(conn, error_views) do
    case List.keyfind(conn.req_headers, "content-type", 0) do
      {"content-type", ct} ->
        Plug.Conn.Utils.content_type(ct)
        |> normalize_content_type()
        |> get_renderer(error_views, conn)
        |> do_render_error(conn)
      nil ->
        "HMAC Error: Please define a content-type for the request"
    end
  end

  defp do_render_error({content_type, error_view, template}, conn) do
    do_render_error({content_type, error_view, template, @default_strategies[content_type]}, conn)
  end
  defp do_render_error({content_type, error_view, template, strategy}, conn) do
    conn |> strategy.(error_view.hmouse_render(template))
  end

  defp normalize_content_type({:ok, _type, "x-www-form-urlencoded", _params}), do: "urlencoded"
  defp normalize_content_type({:ok, _type, subtype, _params} = things) do
    if subtype == "json" || String.ends_with?(subtype, "+json") do
      "json"
    else
      subtype
    end
  end

  defp get_renderer(content_type, error_views, conn) do
    case List.keyfind(error_views, content_type, 0) do
      nil -> raise ArgumentError, "PlugHMouse could not find an error view for content type \"#{conn.content_type}\""
      error_view -> error_view
    end
  end

end
