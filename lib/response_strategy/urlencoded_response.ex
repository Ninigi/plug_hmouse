defmodule PlugHMouse.ResponseStrategy.URLENCODEDResponse do
  import Plug.Conn

  @behaviour PlugHMouse.ResponseStrategy

  def respond(conn, response) do
    conn
    |> put_resp_content_type("text/plain")
    |> resp(403, response)
    |> send_resp()
  end
end
