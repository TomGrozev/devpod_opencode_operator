defmodule DevpodOpencodeOperator.K8s.Connection do
  @moduledoc """
  Supervised holder for a `K8s.Conn.t()`.

  The connection is built once at startup from `KUBECONFIG` (or the
  in-cluster service account) and held in state. Callers fetch the
  current conn with `get/0`. If the process crashes the supervisor
  restarts it, rebuilding the conn from the environment.
  """

  use GenServer

  require Logger

  @name __MODULE__

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

  def start_link(opts \\ []) do
    conn = Keyword.get(opts, :conn) || build_k8s_conn()
    GenServer.start_link(__MODULE__, conn, name: @name)
  end

  @doc "Returns the current `K8s.Conn.t()`. Synchronous."
  @spec get() :: K8s.Conn.t()
  def get, do: GenServer.call(@name, :get)

  # -------------------------------------------------------------------
  # GenServer callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(conn), do: {:ok, conn}

  @impl true
  def handle_call(:get, _from, conn), do: {:reply, conn, conn}

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  defp build_k8s_conn do
    case System.get_env("KUBECONFIG") do
      nil ->
        Logger.info("No KUBECONFIG env var — using in-cluster service account")
        {:ok, conn} = K8s.Conn.from_service_account()
        conn

      path ->
        Logger.info("Loading kubeconfig from #{path}")
        {:ok, conn} = K8s.Conn.from_file(path)
        conn
    end
  end
end
