defmodule PlugHMouse.ResponseStrategy.JSONResponse do
    import Plug.Conn

    @behaviour PlugHMouse.ResponseStrategy

    def respond(conn, response) do
      conn
      |> put_resp_content_type("application/vnd.api+json")
      |> resp(403, Poison.encode!(response))
      |> send_resp()
    end
end
