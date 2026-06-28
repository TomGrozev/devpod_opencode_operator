defmodule DevpodOpencodeOperator.Portal do
  @moduledoc """
  HTTP plug that serves the in-operator portal page.

  Lists operator-owned HTTPRoutes (discovered via the
  `app.kubernetes.io/managed-by=devpod-opencode-operator` label) and
  renders them as anchor cards pointing at each OpenCode Endpoint.

  No authentication — see ADR-0005. Operators needing auth apply it at
  the gateway/proxy layer.
  """

  alias DevpodOpencodeOperator.K8s
  alias DevpodOpencodeOperator.Portal.Template

  require Logger

  @behaviour Plug

  @label_selector "app.kubernetes.io/managed-by=devpod-opencode-operator"
  @workspace_uid_label "devpod.sh/workspace-uid"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    namespace = Keyword.fetch!(opts, :namespace)
    k8s_conn = DevpodOpencodeOperator.K8s.Connection.get()

    case K8s.list_http_routes(k8s_conn, namespace, @label_selector) do
      {:ok, %{items: items}} ->
        endpoints = build_endpoints(items)
        html = Template.render(endpoints)

        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, html)

      {:error, reason} ->
        Logger.warning("Portal failed to list HTTPRoutes: #{inspect(reason)}")

        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(
          500,
          "<!DOCTYPE html><html><head><title>Portal unavailable</title></head>" <>
            "<body><h1>Portal unavailable: could not list endpoints.</h1></body></html>"
        )
    end
  end

  defp build_endpoints(routes) do
    routes
    |> Enum.map(&build_endpoint/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.workspace_id)
  end

  defp build_endpoint(route) do
    workspace_id = get_in(route, ["metadata", "labels", @workspace_uid_label])
    hostname = route |> get_in(["spec", "hostnames"]) |> List.first()

    if workspace_id && hostname do
      %{url: "https://" <> hostname, workspace_id: workspace_id}
    end
  end
end
