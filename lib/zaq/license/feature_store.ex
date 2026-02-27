defmodule Zaq.License.FeatureStore do
  @moduledoc """
  Stores and queries loaded license data and modules.
  Uses an ETS table for fast runtime lookups.
  """

  use GenServer

  @table :zaq_license_features

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Stores license data and loaded module atoms.
  """
  def store(license_data, loaded_modules) do
    GenServer.call(__MODULE__, {:store, license_data, loaded_modules})
  end

  @doc """
  Returns the stored license data, or nil if no license is loaded.
  """
  def license_data do
    case :ets.lookup(@table, :license_data) do
      [{:license_data, data}] -> data
      [] -> nil
    end
  end

  @doc """
  Returns the list of loaded module atoms, or [] if none.
  """
  def loaded_modules do
    case :ets.lookup(@table, :loaded_modules) do
      [{:loaded_modules, modules}] -> modules
      [] -> []
    end
  end

  @doc """
  Returns true if a given feature name is loaded.
  """
  def feature_loaded?(feature_name) do
    case license_data() do
      nil ->
        false

      data ->
        data
        |> Map.get("features", [])
        |> Enum.any?(fn f -> f["name"] == feature_name end)
    end
  end

  @doc """
  Returns true if a given module atom is loaded and available.
  """
  def module_loaded?(module_atom) do
    module_atom in loaded_modules()
  end

  @doc """
  Clears all stored license data and modules.
  """
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :named_table, :protected, read_concurrency: true])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:store, license_data, loaded_modules}, _from, state) do
    :ets.insert(@table, {:license_data, license_data})
    :ets.insert(@table, {:loaded_modules, loaded_modules})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end
end
