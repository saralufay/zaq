# lib/zaq_web/live/bo/dashboard_live.ex

defmodule ZaqWeb.Live.BO.DashboardLive do
  use ZaqWeb, :live_view

  alias Zaq.Accounts
  alias Zaq.License.FeatureStore

  def mount(_params, _session, socket) do
    license_data = FeatureStore.license_data()

    days_left =
      case license_data do
        nil ->
          nil

        data ->
          case DateTime.from_iso8601(data["expires_at"] || "") do
            {:ok, dt, _} -> DateTime.diff(dt, DateTime.utc_now(), :day)
            _ -> nil
          end
      end

    # Roles from config
    active_roles = Application.get_env(:zaq, :roles, [:all])

    services = [
      %{name: "Engine", role: :engine, description: "Sessions, ontology, API routing"},
      %{name: "Agent", role: :agent, description: "RAG, LLM, classifier"},
      %{name: "Ingestion", role: :ingestion, description: "Document processing, embeddings"},
      %{name: "Channels", role: :channels, description: "Mattermost, Slack, Email"},
      %{name: "Back Office", role: :bo, description: "Admin panel (LiveView)"}
    ]

    services =
      Enum.map(services, fn svc ->
        Map.put(svc, :active, :all in active_roles or svc.role in active_roles)
      end)

    {:ok,
     assign(socket,
       current_path: "/bo/dashboard",
       license_data: license_data,
       days_left: days_left,
       services: services,
       user_count: length(Accounts.list_users()),
       # Placeholders — wire up later
       session_count: 0,
       document_count: 0,
       embedding_count: 0,
       channel_count: 0
     )}
  end
end
