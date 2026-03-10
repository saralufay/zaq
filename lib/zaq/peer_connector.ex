defmodule Zaq.PeerConnector do
  @moduledoc """
  Auto-discovers and connects to peer nodes via EPMD — no NODES env var needed.

  On startup and on every nodeup event, queries EPMD for all named nodes
  running on the same host and attempts to connect to each. Nodes with a
  different cookie are silently skipped by the Erlang runtime.

  Broadcasts node up/down events via Phoenix.PubSub so LiveViews can
  react without managing their own monitor_nodes subscriptions.

  ## PubSub messages

      {:node_up, node_name}
      {:node_down, node_name}

  ## Usage

      # Subscribe in a LiveView
      Phoenix.PubSub.subscribe(Zaq.PubSub, "node:events")

      def handle_info({:node_up, _node}, socket), do: ...
      def handle_info({:node_down, _node}, socket), do: ...

  ## Dev commands — no NODES needed

      ROLES=bo           iex --sname bo@localhost       --cookie zaq_dev -S mix phx.server
      ROLES=agent,ingestion iex --sname ai@localhost    --cookie zaq_dev -S mix
      ROLES=channels     iex --sname channels@localhost --cookie zaq_dev -S mix
  """

  use GenServer

  require Logger

  @topic "node:events"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :net_kernel.monitor_nodes(true)
    connect_epmd_peers()
    {:ok, %{}}
  end

  @impl true
  def handle_info({:nodeup, node}, state) do
    Logger.info("[PeerConnector] Node up: #{node}")
    Phoenix.PubSub.broadcast(Zaq.PubSub, @topic, {:node_up, node})
    connect_epmd_peers()
    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, node}, state) do
    Logger.warning("[PeerConnector] Node down: #{node}")
    Phoenix.PubSub.broadcast(Zaq.PubSub, @topic, {:node_down, node})
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # -- Private --

  defp connect_epmd_peers do
    host = host()

    case :erl_epmd.names(host) do
      {:ok, entries} ->
        entries
        |> Enum.map(fn {name, _port} -> :"#{name}@#{host}" end)
        |> Enum.reject(&(&1 == node()))
        |> Enum.each(&connect_peer/1)

      {:error, reason} ->
        Logger.debug("[PeerConnector] EPMD query failed: #{inspect(reason)}")
    end
  end

  defp connect_peer(node) do
    case Node.connect(node) do
      true ->
        Logger.info("[PeerConnector] Connected to: #{node}")

      false ->
        Logger.debug(
          "[PeerConnector] Could not connect to: #{node} (different cookie or unreachable)"
        )

      :ignored ->
        Logger.debug("[PeerConnector] Not distributed, skipping: #{node}")
    end
  end

  defp host do
    node()
    |> Atom.to_string()
    |> String.split("@")
    |> List.last()
    |> String.to_charlist()
  end
end
