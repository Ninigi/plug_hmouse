defmodule PlugHMouse.Render.JSONError do
  def render("403.json") do
    %{"error" => "Invalid HMAC"}
  end
end
