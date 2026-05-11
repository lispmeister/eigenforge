defmodule Eigenforge.Dashboard.ErrorHTML do
  use Phoenix.Component

  def render(_template, assigns) do
    ~H"""
    <section class="panel" style="padding: 24px;">
      <h1>Dashboard Error</h1>
      <p>The dashboard could not render the requested page.</p>
    </section>
    """
  end
end
