defmodule PlugHMouse.Render.JSONError do
  def hmouse_render("403.json") do
    %{"error" => "Invalid HMAC"}
  end
end
