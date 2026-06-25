defmodule DevpodOpencodeOperator.Watcher do
  @moduledoc """
  GenServer that lists all devpod Pods on startup, reconciles each one,
  then watches for further changes using the Kubernetes Watch API.

  On startup or reconnection the watcher performs a full list to seed
  the `resourceVersion`, then enters a long-lived watch loop. When the
  stream ends (server-side timeout, 410 Gone, network error, etc.) the
  watcher retries with exponential backoff, capped at 30 seconds.

  ## State

  * `conn` — a `K8s.Conn.t()` used to talk to the Kubernetes API
  * `config` — a `%DevpodOpencodeOperator.Config{}` struct
  * `resource_version` — last-seen `resourceVersion` for resuming a watch
  * `backoff` — current backoff interval in milliseconds
  """

  use GenServer

  require Logger

  alias DevpodOpencodeOperator.K8s.Cluster
  alias DevpodOpencodeOperator.Reconciler

  @default_backoff 1_000
  @max_backoff 30_000

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Start the watcher linked to the caller.

  ## Options

    * `:conn` — (required) a `K8s.Conn.t()`
    * `:config` — (required) a `%DevpodOpencodeOperator.Config{}`
    * `:backoff` — initial backoff in ms (default: #{@default_backoff})
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    conn = Keyword.fetch!(opts, :conn)
    config = Keyword.fetch!(opts, :config)
    backoff = Keyword.get(opts, :backoff, @default_backoff)

    GenServer.start_link(__MODULE__, %{
      conn: conn,
      config: config,
      resource_version: nil,
      backoff: backoff
    })
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(state) do
    # Kick off the list-then-watch loop asynchronously so init returns
    # immediately.
    send(self(), :list_pods)
    {:ok, state}
  end

  @impl true
  def handle_info(:list_pods, %{config: config, conn: conn} = state) do
    case Cluster.list_pods(conn, namespace: config.target_namespace) do
      {:ok, %{items: items, resource_version: resource_version}} ->
        Logger.info("Listed #{length(items)} pods, resourceVersion=#{inspect(resource_version)}")

        Enum.each(items, fn pod ->
          Reconciler.reconcile(conn, pod, config)
        end)

        new_state = %{state | resource_version: resource_version, backoff: @default_backoff}
        schedule_watch()
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to list pods: #{inspect(reason)}, retrying in #{state.backoff}ms")
        schedule_list_pods(state.backoff)
        {:noreply, %{state | backoff: min(state.backoff * 2, @max_backoff)}}
    end
  end

  @impl true
  def handle_info(:watch, %{config: config, conn: conn} = state) do
    case Cluster.watch_pods(conn, state.resource_version, namespace: config.target_namespace) do
      {:ok, stream} ->
        Logger.info("Watch stream opened from resourceVersion=#{inspect(state.resource_version)}")
        new_state = consume_watch_stream(stream, state)
        {:noreply, new_state}

      {:error, %K8s.Client.APIError{reason: reason}}
      when reason in ["Expired", "Gone"] ->
        Logger.warning(
          "Watch stream rejected with 410 Gone (#{inspect(reason)}), " <>
            "resourceVersion=#{inspect(state.resource_version)} is too old — re-listing"
        )

        send(self(), :list_pods)
        {:noreply, %{state | resource_version: nil, backoff: @default_backoff}}

      {:error, reason} ->
        Logger.error(
          "Failed to open watch stream: #{inspect(reason)}, retrying in #{state.backoff}ms"
        )

        schedule_watch(state.backoff)
        {:noreply, %{state | backoff: min(state.backoff * 2, @max_backoff)}}
    end
  end

  # ---------------------------------------------------------------------------
  # Stream consumption (synchronous, inside the GenServer process)
  # ---------------------------------------------------------------------------

  defp consume_watch_stream(stream, state) do
    final_state =
      Enum.reduce(stream, state, fn event, acc ->
        handle_watch_event(event, acc.config, acc.conn)
        %{acc | resource_version: next_resource_version(event, acc.resource_version)}
      end)

    Logger.info("Watch stream ended, scheduling reconnect in #{final_state.backoff}ms")
    schedule_watch(final_state.backoff)
    %{final_state | backoff: min(final_state.backoff * 2, @max_backoff)}
  rescue
    e ->
      Logger.error("Watch stream error: #{inspect(e)}, reconnecting in #{state.backoff}ms")
      schedule_watch(state.backoff)
      %{state | backoff: min(state.backoff * 2, @max_backoff)}
  catch
    :exit, reason ->
      Logger.error("Watch stream exited: #{inspect(reason)}, reconnecting in #{state.backoff}ms")
      schedule_watch(state.backoff)
      %{state | backoff: min(state.backoff * 2, @max_backoff)}
  end

  defp handle_watch_event(%{"type" => type, "object" => pod}, config, conn)
       when type in ["ADDED", "MODIFIED"] do
    Reconciler.reconcile(conn, pod, config)
  end

  defp handle_watch_event(%{"type" => "DELETED", "object" => pod}, _config, _conn) do
    Logger.debug("Pod deleted: #{get_in(pod, ["metadata", "name"])}")
  end

  defp handle_watch_event(%{"type" => other}, _config, _conn) do
    Logger.warning("Unknown watch event type: #{other}")
  end

  defp next_resource_version(%{"object" => object}, current) do
    case get_in(object, ["metadata", "resourceVersion"]) do
      rv when is_binary(rv) and rv != "" -> rv
      _ -> current
    end
  end

  # ---------------------------------------------------------------------------
  # Scheduling helpers
  # ---------------------------------------------------------------------------

  defp schedule_list_pods(delay) do
    Process.send_after(self(), :list_pods, delay)
  end

  defp schedule_watch(delay \\ 0) do
    Process.send_after(self(), :watch, delay)
  end
end
