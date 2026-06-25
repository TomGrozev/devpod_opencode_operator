defmodule DevpodOpencodeOperator.Application do
  @moduledoc """
  OTP application and supervisor for the DevPod OpenCode Operator.

  Boots a supervision tree that:
    1. Loads configuration from environment variables
    2. Establishes a Kubernetes cluster connection
    3. Starts the pod watcher
  """

  use Application

  require Logger

  alias DevpodOpencodeOperator.Config

  @impl true
  def start(_type, _args) do
    config = Config.load()

    # Build a K8s connection from KUBECONFIG or in-cluster service account.
    conn = build_k8s_conn()

    children = [
      {DevpodOpencodeOperator.Watcher, config: config, conn: conn}
    ]

    opts = [strategy: :one_for_one, name: DevpodOpencodeOperator.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # ---------------------------------------------------------------------------
  # Connection helpers
  # ---------------------------------------------------------------------------

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
