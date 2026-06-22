defmodule DevpodOpencodeOperator.ResourcesTest do
  use ExUnit.Case

  describe "build_service/2" do
    test "returns a Service with name <workspace_id>-opencode" do
      pod = %{
        "metadata" => %{
          "name" => "devpod-abc123",
          "namespace" => "devpod",
          "uid" => "pod-uid-123",
          "labels" => %{
            "devpod.sh/workspace-uid" => "abc123",
            "devpod.sh/created" => "true"
          }
        }
      }

      service = DevpodOpencodeOperator.Resources.build_service(pod, 4096)

      assert get_in(service, ["metadata", "name"]) == "abc123-opencode"
    end

    test "includes ownerReferences pointing at the Pod" do
      pod = %{
        "metadata" => %{
          "name" => "devpod-abc123",
          "namespace" => "devpod",
          "uid" => "pod-uid-123",
          "labels" => %{
            "devpod.sh/workspace-uid" => "abc123"
          }
        }
      }

      service = DevpodOpencodeOperator.Resources.build_service(pod, 4096)

      owner_refs = get_in(service, ["metadata", "ownerReferences"])
      assert length(owner_refs) == 1

      owner = hd(owner_refs)
      assert owner["apiVersion"] == "v1"
      assert owner["kind"] == "Pod"
      assert owner["name"] == "devpod-abc123"
      assert owner["uid"] == "pod-uid-123"
    end

    test "omits ownerReferences when Pod has no UID" do
      pod = %{
        "metadata" => %{
          "name" => "devpod-abc123",
          "namespace" => "devpod",
          "uid" => nil,
          "labels" => %{
            "devpod.sh/workspace-uid" => "abc123"
          }
        }
      }

      service = DevpodOpencodeOperator.Resources.build_service(pod, 4096)

      assert get_in(service, ["metadata", "ownerReferences"]) == nil
    end

    test "omits ownerReferences when Pod metadata has no uid key" do
      pod = %{
        "metadata" => %{
          "name" => "devpod-abc123",
          "namespace" => "devpod",
          "labels" => %{
            "devpod.sh/workspace-uid" => "abc123"
          }
        }
      }

      service = DevpodOpencodeOperator.Resources.build_service(pod, 4096)

      assert get_in(service, ["metadata", "ownerReferences"]) == nil
    end
  end

  describe "build_http_route/4" do
    test "returns an HTTPRoute with correct hostname, parentRef, and backendRef" do
      pod = %{
        "metadata" => %{
          "name" => "devpod-abc123",
          "namespace" => "devpod",
          "uid" => "pod-uid-123",
          "labels" => %{
            "devpod.sh/workspace-uid" => "abc123"
          }
        }
      }

      http_route =
        DevpodOpencodeOperator.Resources.build_http_route(
          pod,
          "devpod.mydomain.com",
          "my-gateway",
          "gateway-ns"
        )

      # Name and namespace
      assert get_in(http_route, ["metadata", "name"]) == "abc123-opencode"
      assert get_in(http_route, ["metadata", "namespace"]) == "devpod"

      # API version and kind
      assert http_route["apiVersion"] == "gateway.networking.k8s.io/v1"
      assert http_route["kind"] == "HTTPRoute"

      # Hostnames
      assert get_in(http_route, ["spec", "hostnames"]) == ["abc123.devpod.mydomain.com"]

      # ParentRefs
      parent_refs = get_in(http_route, ["spec", "parentRefs"])
      assert length(parent_refs) == 1
      assert hd(parent_refs)["name"] == "my-gateway"
      assert hd(parent_refs)["namespace"] == "gateway-ns"

      # Rules - path match and backend ref
      rules = get_in(http_route, ["spec", "rules"])
      assert length(rules) == 1

      matches = hd(rules)["matches"]
      assert length(matches) == 1
      assert get_in(hd(matches), ["path", "type"]) == "PathPrefix"
      assert get_in(hd(matches), ["path", "value"]) == "/"

      backend_refs = hd(rules)["backendRefs"]
      assert length(backend_refs) == 1
      assert hd(backend_refs)["name"] == "abc123-opencode"
      assert hd(backend_refs)["port"] == 80
    end

    test "includes ownerReferences pointing at the Pod" do
      pod = %{
        "metadata" => %{
          "name" => "devpod-abc123",
          "namespace" => "devpod",
          "uid" => "pod-uid-123",
          "labels" => %{
            "devpod.sh/workspace-uid" => "abc123"
          }
        }
      }

      http_route =
        DevpodOpencodeOperator.Resources.build_http_route(
          pod,
          "devpod.mydomain.com",
          "my-gateway",
          "gateway-ns"
        )

      owner_refs = get_in(http_route, ["metadata", "ownerReferences"])
      assert length(owner_refs) == 1

      owner = hd(owner_refs)
      assert owner["apiVersion"] == "v1"
      assert owner["kind"] == "Pod"
      assert owner["name"] == "devpod-abc123"
      assert owner["uid"] == "pod-uid-123"
    end

    test "omits ownerReferences when Pod has no UID" do
      pod = %{
        "metadata" => %{
          "name" => "devpod-abc123",
          "namespace" => "devpod",
          "labels" => %{
            "devpod.sh/workspace-uid" => "abc123"
          }
        }
      }

      http_route =
        DevpodOpencodeOperator.Resources.build_http_route(
          pod,
          "devpod.mydomain.com",
          "my-gateway",
          "gateway-ns"
        )

      assert get_in(http_route, ["metadata", "ownerReferences"]) == nil
    end
  end
end
