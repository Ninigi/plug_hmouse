defmodule PlugHMouse.RenderStrategy.JSONError do
  @behaviour PlugHMouse.RenderStrategy

  def hmouse_render("403.json") do
    %{"error" => "Invalid HMAC"}
  end
end
