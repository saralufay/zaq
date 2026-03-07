defmodule ZaqWeb.Live.BO.Widget.SettingsLive do
  use ZaqWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Widget Settings")
     |> assign(:current_path, "/bo/widget-settings")}
  end
end
