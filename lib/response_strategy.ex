defmodule PlugHMouse.ResponseStrategy do
  @moduledoc """
  Use `@behaviour PlugHMouse.ResponseStrategy` to define custom response functions.

  ## Example
      defmodule MyApp.ResponseStrategy.JSONResponse do
        import Plug.Conn

        @behaviour PlugHMouse.ResponseStrategy

        def respond(conn, response) do
          IO.puts "I want to log this!"

          # ... Do some other stuff

          # It is your responsibility to send the response
          conn
          |> put_resp_content_type("application/vnd.api+json")
          |> resp(401, Poison.encode!(%{"Reason" => response}))
          |> send_resp()
        end
      end

      plug PlugHMouse,
        validate: {"x-shopify-hmac-sha256", "MyKey"},
        error_views:
          [{"json", PlugHMouse.RenderStrategy.JSONError, "403.json", MyApp.ResponseStrategy}]
  """

  @callback respond(conn :: Plug.Conn.t, response :: String.t | Map.t) :: Plug.Conn.t
end
