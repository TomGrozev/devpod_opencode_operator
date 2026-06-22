defmodule DevpodOpencodeOperator.Resources do
  @moduledoc """
  Generates Kubernetes Service and HTTPRoute manifests from a Pod map.
  """

  def build_service(pod, target_port) do
    workspace_id = get_in(pod, ["metadata", "labels", "devpod.sh/workspace-uid"])
    namespace = get_in(pod, ["metadata", "namespace"])

    metadata = %{
      "name" => "#{workspace_id}-opencode",
      "namespace" => namespace
    }

    metadata = maybe_add_owner_reference(metadata, pod)

    %{
      "apiVersion" => "v1",
      "kind" => "Service",
      "metadata" => metadata,
      "spec" => %{
        "type" => "ClusterIP",
        "selector" => %{
          "devpod.sh/workspace-uid" => workspace_id
        },
        "ports" => [
          %{
            "port" => 80,
            "targetPort" => target_port
          }
        ]
      }
    }
  end

  def build_http_route(pod, base_domain, gateway_name, gateway_namespace) do
    workspace_id = get_in(pod, ["metadata", "labels", "devpod.sh/workspace-uid"])
    namespace = get_in(pod, ["metadata", "namespace"])

    metadata = %{
      "name" => "#{workspace_id}-opencode",
      "namespace" => namespace
    }

    metadata = maybe_add_owner_reference(metadata, pod)

    %{
      "apiVersion" => "gateway.networking.k8s.io/v1",
      "kind" => "HTTPRoute",
      "metadata" => metadata,
      "spec" => %{
        "parentRefs" => [
          %{
            "name" => gateway_name,
            "namespace" => gateway_namespace
          }
        ],
        "hostnames" => ["#{workspace_id}.#{base_domain}"],
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
                "name" => "#{workspace_id}-opencode",
                "port" => 80
              }
            ]
          }
        ]
      }
    }
  end

  defp maybe_add_owner_reference(metadata, pod) do
    case get_in(pod, ["metadata", "uid"]) do
      nil ->
        metadata

      uid ->
        owner_ref = %{
          "apiVersion" => "v1",
          "kind" => "Pod",
          "name" => get_in(pod, ["metadata", "name"]),
          "uid" => uid
        }

        Map.put(metadata, "ownerReferences", [owner_ref])
    end
  end
end
