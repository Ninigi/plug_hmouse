defmodule PlugHMouse.RenderStrategy.URLENCODEDError do
  @behaviour PlugHMouse.RenderStrategy

  def hmouse_render("403") do
    "Error: Invalid HMAC"
  end
end
