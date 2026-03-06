defmodule ZaqWeb.Live.BO.Accounts.UsersLive do
  use ZaqWeb, :live_view

  alias Zaq.Accounts

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:users, Accounts.list_users())
     |> assign(:current_path, "/bo/users")}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    case Accounts.delete_user(user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "User deleted.")
         |> assign(:users, Accounts.list_users())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete user.")}
    end
  end
end
