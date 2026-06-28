defmodule DevpodOpencodeOperator.Application do
  @moduledoc """
  OTP application and supervisor for the DevPod OpenCode Operator.

  Boots a supervision tree that:
    1. Loads configuration from environment variables
    2. Establishes a supervised Kubernetes cluster connection
    3. Starts the pod watcher
    4. Starts the Bandit HTTP listener serving the in-operator portal
  """

  use Application

  require Logger

  alias DevpodOpencodeOperator.Config

  @impl true
  def start(_type, _args) do
    config = Config.load()

    children = [
      DevpodOpencodeOperator.K8s.Connection,
      {DevpodOpencodeOperator.Watcher, config: config},
      {Bandit,
       plug: {DevpodOpencodeOperator.Portal, namespace: config.target_namespace},
       scheme: :http,
       port: config.portal_port}
    ]

    opts = [strategy: :one_for_one, name: DevpodOpencodeOperator.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
