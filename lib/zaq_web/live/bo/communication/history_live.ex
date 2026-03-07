defmodule ZaqWeb.Live.BO.Communication.HistoryLive do
  use ZaqWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "History")
     |> assign(:current_path, "/bo/history")}
  end
end
