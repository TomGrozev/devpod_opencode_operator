defmodule DevpodOpencodeOperator.Reconciler do
  @moduledoc """
  Reconciles a single devpod Pod by applying a Service and HTTPRoute.
  Stateless — the only API state read on the hot path is the existing
  Service's `metadata.resourceVersion` (to distinguish CREATE vs UPDATE).
  """

  alias DevpodOpencodeOperator.Config
  alias DevpodOpencodeOperator.K8s, as: Cluster
  alias DevpodOpencodeOperator.Resources

  require Logger

  @port_annotation "devpod.sh/opencode-port"
  @workspace_uid_label "devpod.sh/workspace-uid"

  @type result :: :ok | {:skipped, term()} | {:error, term()}

  @spec reconcile(K8s.Conn.t(), map(), Config.t()) :: result()
  def reconcile(conn, pod, %Config{} = config) do
    workspace_id = get_in(pod, ["metadata", "labels", @workspace_uid_label])

    case workspace_id do
      nil ->
        Logger.warning("Skipping pod without #{@workspace_uid_label} label")
        {:skipped, :missing_workspace_uid_label}

      workspace_id ->
        reconcile_with_workspace(conn, pod, config, workspace_id)
    end
  end

  defp reconcile_with_workspace(conn, pod, config, workspace_id) do
    namespace = get_in(pod, ["metadata", "namespace"])
    resource_name = "#{workspace_id}-opencode"

    # Read existing Service to distinguish CREATE from UPDATE.
    # A get error is non-fatal — we treat it as CREATE and apply anyway
    # (the apply is server-side, idempotent).
    operation =
      conn
      |> Cluster.get(:Service, resource_name, namespace: namespace)
      |> operation_from()

    # Build manifests (pure, no side effects)
    target_port = resolve_port(pod, config)
    service = Resources.build_service(pod, target_port)

    http_route =
      Resources.build_http_route(
        pod,
        config.base_domain,
        config.gateway_name,
        config.gateway_namespace
      )

    with {:ok, _service} <- Cluster.apply(conn, :Service, resource_name, service),
         {:ok, _route} <- Cluster.apply(conn, :HTTPRoute, resource_name, http_route) do
      Logger.info("Reconciled workspace: #{String.upcase(to_string(operation))}",
        workspace_id: workspace_id
      )

      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to apply #{resource_name}: #{inspect(reason)}",
          workspace_id: workspace_id
        )

        {:error, reason}
    end
  end

  # Determine the operation type from the get result.
  #
  # resourceVersion present and non-empty ⇒ UPDATE; otherwise ⇒ CREATE.
  # A get error is treated as CREATE — the apply is idempotent and the
  # reconcile itself remains stateless.
  defp operation_from(get_result) do
    case get_result do
      {:ok, nil} ->
        :create

      {:ok, %{"metadata" => %{"resourceVersion" => v}}} when is_binary(v) and v != "" ->
        :update

      {:ok, _} ->
        :create

      {:error, _reason} ->
        :create
    end
  end

  defp resolve_port(pod, config) do
    case get_in(pod, ["metadata", "annotations", @port_annotation]) do
      nil ->
        config.default_port

      port_str ->
        case Integer.parse(port_str) do
          {port, ""} -> port
          _ -> config.default_port
        end
    end
  end
end
