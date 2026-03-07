defmodule ZaqWeb.Live.BO.Communication.PlaygroundLive do
  use ZaqWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Playground")
     |> assign(:current_path, "/bo/playground")}
  end
end
