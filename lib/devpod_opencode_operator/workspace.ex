defmodule DevpodOpencodeOperator.Workspace do
  @moduledoc """
  Represents a single devpod workspace derived from a Pod map.

  A workspace carries everything the operator needs to build a Service
  and HTTPRoute for one devpod instance: a human-friendly `id`, the
  devpod `uid`, the K8s resource name, namespace, the resolved OpenCode
  port, and the owner reference pointing back at the source Pod.
  """

  require Logger

  alias DevpodOpencodeOperator.Config

  @workspace_uid_label "devpod.sh/workspace-uid"
  @devpod_workspace_id_env "DEVPOD_WORKSPACE_ID"
  @port_annotation "devpod.sh/opencode-port"

  defstruct [:id, :uid, :name, :namespace, :port, :owner_reference]

  @type t :: %__MODULE__{
          id: String.t(),
          uid: String.t(),
          name: String.t(),
          namespace: String.t(),
          port: 0..65535,
          owner_reference: map() | nil
        }

  @doc """
  Builds a Workspace from a Pod map and runtime config.

  Returns `{:ok, workspace}` on success, or `:error` when the pod
  is missing the required `devpod.sh/workspace-uid` label or namespace.

  The `id` field is populated from the `DEVPOD_WORKSPACE_ID` env var
  on the devpod container, falling back to the workspace-uid label value.
  The `uid` field always holds the workspace-uid label value.
  """
  @spec from_pod(map(), Config.t()) :: {:ok, t()} | :error
  def from_pod(pod, %Config{} = config) do
    with {:ok, uid} <- fetch_uid(pod),
         {:ok, namespace} <- fetch_namespace(pod) do
      id = fetch_friendly_id(pod) || uid

      {:ok,
       %__MODULE__{
         id: id,
         uid: uid,
         name: "#{uid}-opencode",
         namespace: namespace,
         port: resolve_port(pod, config),
         owner_reference: build_owner_reference(pod)
       }}
    end
  end

  defp fetch_uid(pod) do
    case get_in(pod, ["metadata", "labels", @workspace_uid_label]) do
      nil -> :error
      uid -> {:ok, uid}
    end
  end

  defp fetch_friendly_id(pod) do
    case find_env_value(pod, @devpod_workspace_id_env) do
      nil ->
        Logger.warning(
          "DEVPOD_WORKSPACE_ID not set on devpod container; falling back to workspace-uid as id"
        )

        nil

      id ->
        id
    end
  end

  defp find_env_value(pod, name) do
    pod
    |> get_in(["spec", "containers"])
    |> Kernel.||([])
    |> Enum.find_value(fn container ->
      env = get_in(container, ["env"]) || []

      case Enum.find(env, fn e -> e["name"] == name end) do
        %{"value" => v} -> v
        _ -> nil
      end
    end)
  end

  defp fetch_namespace(pod) do
    case get_in(pod, ["metadata", "namespace"]) do
      nil -> :error
      ns -> {:ok, ns}
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

  defp build_owner_reference(pod) do
    case get_in(pod, ["metadata", "uid"]) do
      nil ->
        nil

      uid ->
        %{
          "apiVersion" => "v1",
          "kind" => "Pod",
          "name" => get_in(pod, ["metadata", "name"]),
          "uid" => uid
        }
    end
  end
end
