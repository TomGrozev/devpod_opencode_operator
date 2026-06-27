defmodule DevpodOpencodeOperator.Reconciler do
  @moduledoc """
  Reconciles a single devpod Pod by applying a Service and HTTPRoute.
  Stateless — no API state is read on the hot path; the apply is
  server-side and idempotent.
  """

  alias DevpodOpencodeOperator.Config
  alias DevpodOpencodeOperator.K8s, as: Cluster
  alias DevpodOpencodeOperator.Resources
  alias DevpodOpencodeOperator.Workspace

  require Logger

  @workspace_uid_label "devpod.sh/workspace-uid"

  @type result :: :ok | {:skipped, term()} | {:error, term()}

  @spec reconcile(K8s.Conn.t(), map(), Config.t()) :: result()
  def reconcile(conn, pod, %Config{} = config) do
    case Workspace.from_pod(pod, config) do
      {:ok, workspace} ->
        reconcile_with_workspace(conn, pod, config, workspace)

      :error ->
        Logger.warning("Skipping pod without #{@workspace_uid_label} label")
        {:skipped, :missing_workspace_uid_label}
    end
  end

  defp reconcile_with_workspace(conn, _pod, config, %Workspace{} = workspace) do
    # Build manifests (pure, no side effects)
    service = Resources.build_service(workspace)
    http_route = Resources.build_http_route(workspace, config)

    with {:ok, _service} <- Cluster.apply(conn, :Service, workspace.name, service),
         {:ok, _route} <- Cluster.apply(conn, :HTTPRoute, workspace.name, http_route) do
      Logger.info("Reconciled workspace", workspace_id: workspace.id)

      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to apply #{workspace.name}: #{inspect(reason)}",
          workspace_id: workspace.id
        )

        {:error, reason}
    end
  end
end
