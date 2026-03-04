defmodule Zaq.License.LicenseWatcherFS do
  @moduledoc """
  A GenServer that watches a directory for .zaq-license files using the file_system library.
  This version uses OS-level file system events instead of polling for better performance.

  ## Dependencies

  Add to your mix.exs:
      {:file_system, "~> 1.0"}

  ## Usage

  Add to your supervision tree:
      children = [
        {Zaq.License.LicenseWatcherFS, watch_dir: "priv/licenses"}
      ]
  """

  use GenServer

  require Logger

  alias Zaq.License.Loader

  @default_watch_dir "priv/licenses"
  @license_pattern ~r/\.zaq-license$/

  defstruct [
    :watch_dir,
    :fs_pid,
    :loaded_licenses,
    :license_mtimes,
    :status,
    :debounce_ref
  ]

  # Client API

  @doc """
  Starts the license watcher with file system events.
  Options:
    - :watch_dir - Directory to watch for license files (default: "priv/licenses")
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the current status of the license watcher.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Forces an immediate scan of the license directory.
  """
  def force_scan do
    GenServer.call(__MODULE__, :force_scan)
  end

  @doc """
  Returns the list of currently loaded licenses.
  """
  def loaded_licenses do
    GenServer.call(__MODULE__, :loaded_licenses)
  end

  @doc """
  Unloads a specific license by its key.
  """
  def unload_license(license_key) do
    GenServer.call(__MODULE__, {:unload, license_key})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    watch_dir = Keyword.get(opts, :watch_dir, @default_watch_dir)

    # Ensure directory exists
    case File.mkdir_p(watch_dir) do
      :ok ->
        state = %__MODULE__{
          watch_dir: watch_dir,
          loaded_licenses: %{},
          license_mtimes: %{},
          status: :starting
        }

        # Start file system watcher
        case start_file_watcher(watch_dir) do
          {:ok, fs_pid} ->
            Logger.info("License watcher started, monitoring: #{watch_dir}")
            # Do initial scan
            new_state = do_scan(%{state | fs_pid: fs_pid})
            {:ok, new_state}

          {:error, reason} ->
            Logger.error("Failed to start file watcher: #{inspect(reason)}")
            {:stop, {:failed_to_start_watcher, reason}}
        end

      {:error, reason} ->
        Logger.error("Failed to create license directory: #{inspect(reason)}")
        {:stop, {:failed_to_create_dir, reason}}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, build_status_response(state), state}
  end

  @impl true
  def handle_call(:force_scan, _from, state) do
    new_state = do_scan(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:loaded_licenses, _from, state) do
    licenses = Map.keys(state.loaded_licenses)
    {:reply, {:ok, licenses}, state}
  end

  @impl true
  def handle_call({:unload, license_key}, _from, state) do
    case Map.get(state.loaded_licenses, license_key) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _license_info ->
        new_state = unload_license_by_key(state, license_key)
        Logger.info("Unloaded license: #{license_key}")
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_info({:file_event, _fs_pid, {path, events}}, state) do
    # Check if this is a license file
    if Regex.match?(@license_pattern, path) do
      Logger.debug("License file event: #{path} - #{inspect(events)}")

      # Debounce rapid file events (e.g., during file writes)
      state = cancel_debounce(state)
      ref = Process.send_after(self(), :process_changes, 500)
      {:noreply, %{state | debounce_ref: ref}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:file_event, _fs_pid, :stop}, state) do
    Logger.warning("File watcher stopped unexpectedly")
    {:noreply, %{state | status: {:error, :watcher_stopped}}}
  end

  @impl true
  def handle_info(:process_changes, state) do
    new_state = do_scan(state)
    {:noreply, %{new_state | debounce_ref: nil}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{fs_pid: fs_pid} = state)
      when pid == fs_pid do
    Logger.error("File system watcher crashed: #{inspect(reason)}")
    {:noreply, %{state | status: {:error, :watcher_crashed}}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp start_file_watcher(watch_dir) do
    # Use the file_system library API
    # https://hexdocs.pm/file_system/1.1.1/readme.html
    case FileSystem.start_link(dirs: [watch_dir]) do
      {:ok, pid} ->
        # Subscribe to file system events
        FileSystem.subscribe(pid)
        # Monitor the file system process
        Process.monitor(pid)
        {:ok, pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cancel_debounce(%{debounce_ref: nil} = state), do: state

  defp cancel_debounce(%{debounce_ref: ref} = state) do
    Process.cancel_timer(ref)
    %{state | debounce_ref: nil}
  end

  defp do_scan(state) do
    Logger.debug("Scanning license directory: #{state.watch_dir}")

    case find_license_files(state.watch_dir) do
      {:ok, files} ->
        process_license_files(state, files)

      {:error, reason} ->
        Logger.warning("Failed to scan license directory: #{inspect(reason)}")
        %{state | status: {:error, reason}}
    end
  end

  defp find_license_files(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        license_files =
          files
          |> Enum.filter(&Regex.match?(@license_pattern, &1))
          |> Enum.map(&Path.join(dir, &1))

        {:ok, license_files}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_license_files(state, files) do
    # Check for new or modified files
    {new_state, results} =
      Enum.reduce(files, {state, []}, fn file_path, {s, acc} ->
        case check_file_status(s, file_path) do
          {:new, path} ->
            {new_s, result} = load_license_file(s, path)
            {new_s, [result | acc]}

          {:modified, path} ->
            Logger.info("License file modified, reloading: #{path}")
            new_s = unload_by_path(s, path)
            {loaded_s, result} = load_license_file(new_s, path)
            {loaded_s, [result | acc]}

          :unchanged ->
            {s, acc}
        end
      end)

    # Check for deleted licenses
    final_state = check_for_deleted_licenses(new_state, files)

    # Update status based on results
    status = determine_status(final_state, results)
    %{final_state | status: status}
  end

  defp check_file_status(state, file_path) do
    case File.stat(file_path) do
      {:ok, %File.Stat{mtime: mtime}} ->
        stored_mtime = Map.get(state.license_mtimes, file_path)

        cond do
          is_nil(stored_mtime) ->
            {:new, file_path}

          stored_mtime != mtime ->
            {:modified, file_path}

          true ->
            :unchanged
        end

      {:error, _reason} ->
        :unchanged
    end
  end

  defp load_license_file(state, file_path) do
    Logger.info("Loading license file: #{file_path}")

    case Loader.load(file_path) do
      {:ok, license_data} ->
        license_key = Map.get(license_data, "license_key", "unknown")
        mtime = get_file_mtime(file_path)

        license_info = %{
          path: file_path,
          data: license_data,
          loaded_at: DateTime.utc_now(),
          mtime: mtime
        }

        new_state = %{
          state
          | loaded_licenses: Map.put(state.loaded_licenses, license_key, license_info),
            license_mtimes: Map.put(state.license_mtimes, file_path, mtime)
        }

        Logger.info("License loaded successfully: #{license_key}")
        {new_state, {:ok, license_key}}

      {:error, reason} ->
        Logger.error("Failed to load license #{file_path}: #{inspect(reason)}")
        {state, {:error, reason}}
    end
  end

  defp unload_by_path(state, file_path) do
    case find_license_by_path(state.loaded_licenses, file_path) do
      {:ok, license_key} ->
        unload_license_by_key(state, license_key)

      :not_found ->
        state
    end
  end

  defp find_license_by_path(loaded_licenses, path) do
    case Enum.find(loaded_licenses, fn {_key, info} -> info.path == path end) do
      {license_key, _info} -> {:ok, license_key}
      nil -> :not_found
    end
  end

  defp unload_license_by_key(state, license_key) do
    case Map.get(state.loaded_licenses, license_key) do
      nil ->
        state

      license_info ->
        new_loaded = Map.delete(state.loaded_licenses, license_key)
        new_mtimes = Map.delete(state.license_mtimes, license_info.path)

        %{state | loaded_licenses: new_loaded, license_mtimes: new_mtimes}
    end
  end

  defp check_for_deleted_licenses(state, current_files) do
    current_file_set = MapSet.new(current_files)

    deleted_paths =
      state.license_mtimes
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(current_file_set, &1))

    Enum.reduce(deleted_paths, state, fn path, s ->
      Logger.warning("License file deleted: #{path}")
      unload_by_path(s, path)
    end)
  end

  defp get_file_mtime(file_path) do
    case File.stat(file_path) do
      {:ok, %File.Stat{mtime: mtime}} -> mtime
      {:error, _} -> nil
    end
  end

  defp determine_status(state, results) do
    loaded_count =
      length(
        Enum.filter(results, fn
          {:ok, _} -> true
          _ -> false
        end)
      )

    total_loaded = map_size(state.loaded_licenses)

    cond do
      total_loaded > 0 ->
        {:ok, %{loaded: total_loaded}}

      loaded_count == 0 and results == [] ->
        {:ok, %{loaded: 0, message: "No license files found"}}

      true ->
        {:warning, %{loaded: total_loaded, failed: length(results) - loaded_count}}
    end
  end

  defp build_status_response(state) do
    %{
      watch_dir: state.watch_dir,
      loaded_count: map_size(state.loaded_licenses),
      licenses: Map.keys(state.loaded_licenses),
      status: state.status
    }
  end
end
