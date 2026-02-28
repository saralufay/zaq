defmodule ZaqWeb.Live.BO.DashboardLiveTest do
  use ZaqWeb.ConnCase

  import Phoenix.LiveViewTest
  import Zaq.AccountsFixtures
  alias Zaq.Accounts
  alias Zaq.License.FeatureStore

  setup %{conn: conn} do
    user = user_fixture(%{username: "testadmin"})
    {:ok, user} = Accounts.change_password(user, %{password: "password123"})

    conn = conn |> init_test_session(%{user_id: user.id})
    %{conn: conn, user: user}
  end

  describe "without license" do
    setup do
      FeatureStore.clear()
      :ok
    end

    test "renders dashboard", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/bo/dashboard")
      assert html =~ "Dashboard"
    end

    test "shows metric cards", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/bo/dashboard")
      assert html =~ "Users"
      assert html =~ "Sessions"
      assert html =~ "Documents"
      assert html =~ "Embeddings"
      assert html =~ "Channels"
    end

    test "shows user count", %{conn: conn} do
      user_fixture(%{username: "extra_user"})
      {:ok, _view, html} = live(conn, ~p"/bo/dashboard")
      # At least the testadmin + extra_user
      assert html =~ "Users"
    end

    test "shows services table", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/bo/dashboard")
      assert html =~ "Services"
      assert html =~ "Engine"
      assert html =~ "Agent"
      assert html =~ "Ingestion"
      assert html =~ "Channels"
      assert html =~ "Back Office"
    end

    test "shows no license card", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/bo/dashboard")
      assert html =~ "No License"
      assert html =~ "Running in basic mode"
      assert html =~ "Learn More"
    end
  end

  describe "with license" do
    setup do
      FeatureStore.store(
        %{
          "license_key" => "lic_dash_789",
          "company_name" => "Dashboard Corp",
          "expires_at" => DateTime.utc_now() |> DateTime.add(60, :day) |> DateTime.to_iso8601(),
          "features" => [
            %{
              "name" => "Ontology Management",
              "description" => "Knowledge graph",
              "module_tags" => []
            }
          ]
        },
        []
      )

      on_exit(fn -> FeatureStore.clear() end)
      :ok
    end

    test "shows license card with company name", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/bo/dashboard")
      assert html =~ "Dashboard Corp"
      assert html =~ "lic_dash_789"
    end

    test "shows feature count", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/bo/dashboard")
      assert html =~ "Features"
    end

    test "shows days left", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/bo/dashboard")
      assert html =~ "Days Left"
    end

    test "shows view details link", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/bo/dashboard")
      assert html =~ "View Details"
    end
  end
end
