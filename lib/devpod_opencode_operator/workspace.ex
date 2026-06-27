defmodule DevpodOpencodeOperator.Workspace do
  @moduledoc """
  Represents a single devpod workspace derived from a Pod map.

  A workspace carries everything the operator needs to build a Service
  and HTTPRoute for one devpod instance: identity, K8s name and
  namespace, the resolved OpenCode port, and the owner reference
  pointing back at the source Pod.
  """

  alias DevpodOpencodeOperator.Config

  @workspace_uid_label "devpod.sh/workspace-uid"
  @port_annotation "devpod.sh/opencode-port"

  defstruct [:id, :name, :namespace, :port, :owner_reference]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          namespace: String.t(),
          port: 0..65535,
          owner_reference: map() | nil
        }

  @doc """
  Builds a Workspace from a Pod map and runtime config.

  Returns `{:ok, workspace}` on success, or `:error` when the pod
  is missing the required `devpod.sh/workspace-uid` label or namespace.
  """
  @spec from_pod(map(), Config.t()) :: {:ok, t()} | :error
  def from_pod(pod, %Config{} = config) do
    with {:ok, id} <- fetch_id(pod),
         {:ok, namespace} <- fetch_namespace(pod) do
      {:ok,
       %__MODULE__{
         id: id,
         name: "#{id}-opencode",
         namespace: namespace,
         port: resolve_port(pod, config),
         owner_reference: build_owner_reference(pod)
       }}
    end
  end

  defp fetch_id(pod) do
    case get_in(pod, ["metadata", "labels", @workspace_uid_label]) do
      nil -> :error
      id -> {:ok, id}
    end
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
