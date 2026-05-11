defmodule Eigenforge.Dashboard.ErrorJSON do
  def render(_template, _assigns), do: %{error: %{message: "dashboard error"}}
end
