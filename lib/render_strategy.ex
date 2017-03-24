defmodule PlugHMouse.RenderStrategy do
  @moduledoc """
  Use `@behaviour PlugHMouse.RenderStrategy` to define custom render functions.
  """
  @callback hmouse_render(template :: String.t) :: String.t | Map.t
end
