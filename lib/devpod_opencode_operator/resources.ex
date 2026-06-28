defmodule DevpodOpencodeOperator.Resources do
  @moduledoc """
  Generates Kubernetes Service and HTTPRoute manifests from a Workspace struct.
  """

  alias DevpodOpencodeOperator.Workspace

  @managed_by_label "app.kubernetes.io/managed-by"
  @managed_by_value "devpod-opencode-operator"
  @workspace_uid_label "devpod.sh/workspace-uid"

  @spec build_service(Workspace.t()) :: map
  def build_service(%Workspace{} = workspace) do
    metadata = %{
      "name" => workspace.name,
      "namespace" => workspace.namespace,
      "labels" => %{@managed_by_label => @managed_by_value}
    }

    metadata = maybe_add_owner_reference(metadata, workspace.owner_reference)

    %{
      "apiVersion" => "v1",
      "kind" => "Service",
      "metadata" => metadata,
      "spec" => %{
        "type" => "ClusterIP",
        "selector" => %{
          @workspace_uid_label => workspace.id
        },
        "ports" => [
          %{
            "port" => 80,
            "targetPort" => workspace.port
          }
        ]
      }
    }
  end

  @spec build_http_route(Workspace.t(), map) :: map
  def build_http_route(%Workspace{} = workspace, config) do
    metadata = %{
      "name" => workspace.name,
      "namespace" => workspace.namespace,
      "labels" => %{
        @managed_by_label => @managed_by_value,
        @workspace_uid_label => workspace.id
      }
    }

    metadata = maybe_add_owner_reference(metadata, workspace.owner_reference)

    %{
      "apiVersion" => "gateway.networking.k8s.io/v1",
      "kind" => "HTTPRoute",
      "metadata" => metadata,
      "spec" => %{
        "parentRefs" => [
          %{
            "name" => config.gateway_name,
            "namespace" => config.gateway_namespace
          }
        ],
        "hostnames" => ["#{workspace.id}.#{config.base_domain}"],
        "rules" => [
          %{
            "matches" => [
              %{
                "path" => %{
                  "type" => "PathPrefix",
                  "value" => "/"
                }
              }
            ],
            "backendRefs" => [
              %{
                "name" => workspace.name,
                "port" => 80
              }
            ]
          }
        ]
      }
    }
  end

  defp maybe_add_owner_reference(metadata, nil), do: metadata

  defp maybe_add_owner_reference(metadata, owner_ref) do
    Map.put(metadata, "ownerReferences", [owner_ref])
  end
end
