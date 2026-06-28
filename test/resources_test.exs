defmodule DevpodOpencodeOperator.ResourcesTest do
  use ExUnit.Case

  alias DevpodOpencodeOperator.Config
  alias DevpodOpencodeOperator.Workspace

  @config %Config{
    target_namespace: "devpod",
    base_domain: "devpod.mydomain.com",
    default_port: 4096,
    gateway_name: "my-gateway",
    gateway_namespace: "gateway-ns"
  }

  describe "build_service/1" do
    test "returns a Service with name <workspace_id>-opencode" do
      workspace = %Workspace{
        id: "abc123",
        uid: "abc123",
        name: "abc123-opencode",
        namespace: "devpod",
        port: 4096,
        owner_reference: %{
          "apiVersion" => "v1",
          "kind" => "Pod",
          "name" => "devpod-abc123",
          "uid" => "pod-uid-123"
        }
      }

      service = DevpodOpencodeOperator.Resources.build_service(workspace)

      assert get_in(service, ["metadata", "name"]) == "abc123-opencode"
    end

    test "uses uid for name and selector, friendly id for label when id differs from uid" do
      workspace = %Workspace{
        id: "my-project",
        uid: "default-po-3e6db",
        name: "default-po-3e6db-opencode",
        namespace: "devpod",
        port: 4096,
        owner_reference: nil
      }

      service = DevpodOpencodeOperator.Resources.build_service(workspace)

      assert get_in(service, ["metadata", "name"]) == "default-po-3e6db-opencode"

      assert get_in(service, ["spec", "selector"]) == %{
               "devpod.sh/workspace-uid" => "default-po-3e6db"
             }

      assert get_in(service, ["metadata", "labels", "devpod.sh/workspace"]) == "my-project"
    end

    test "includes ownerReferences when owner_reference is set" do
      workspace = %Workspace{
        id: "abc123",
        uid: "abc123",
        name: "abc123-opencode",
        namespace: "devpod",
        port: 4096,
        owner_reference: %{
          "apiVersion" => "v1",
          "kind" => "Pod",
          "name" => "devpod-abc123",
          "uid" => "pod-uid-123"
        }
      }

      service = DevpodOpencodeOperator.Resources.build_service(workspace)

      assert get_in(service, ["metadata", "ownerReferences"]) == [
               %{
                 "apiVersion" => "v1",
                 "kind" => "Pod",
                 "name" => "devpod-abc123",
                 "uid" => "pod-uid-123"
               }
             ]
    end

    test "omits ownerReferences when Pod has no UID" do
      workspace = %Workspace{
        id: "abc123",
        uid: "abc123",
        name: "abc123-opencode",
        namespace: "devpod",
        port: 4096,
        owner_reference: nil
      }

      service = DevpodOpencodeOperator.Resources.build_service(workspace)

      assert get_in(service, ["metadata", "ownerReferences"]) == nil
    end

    test "omits ownerReferences when Pod metadata has no uid key" do
      workspace = %Workspace{
        id: "abc123",
        uid: "abc123",
        name: "abc123-opencode",
        namespace: "devpod",
        port: 4096,
        owner_reference: nil
      }

      service = DevpodOpencodeOperator.Resources.build_service(workspace)

      assert get_in(service, ["metadata", "ownerReferences"]) == nil
    end

    test "includes app.kubernetes.io/managed-by label set to devpod-opencode-operator" do
      workspace = %Workspace{
        id: "abc123",
        uid: "abc123",
        name: "abc123-opencode",
        namespace: "devpod",
        port: 4096,
        owner_reference: %{
          "apiVersion" => "v1",
          "kind" => "Pod",
          "name" => "devpod-abc123",
          "uid" => "pod-uid-123"
        }
      }

      service = DevpodOpencodeOperator.Resources.build_service(workspace)

      labels = get_in(service, ["metadata", "labels"])
      assert labels["app.kubernetes.io/managed-by"] == "devpod-opencode-operator"
      assert labels["devpod.sh/workspace"] == "abc123"
    end
  end

  describe "build_http_route/2" do
    test "returns an HTTPRoute with correct hostname, parentRef, and backendRef" do
      workspace = %Workspace{
        id: "abc123",
        uid: "abc123",
        name: "abc123-opencode",
        namespace: "devpod",
        port: 4096,
        owner_reference: %{
          "apiVersion" => "v1",
          "kind" => "Pod",
          "name" => "devpod-abc123",
          "uid" => "pod-uid-123"
        }
      }

      http_route = DevpodOpencodeOperator.Resources.build_http_route(workspace, @config)

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

    test "uses uid for name and hostname, friendly id for label when id differs from uid" do
      workspace = %Workspace{
        id: "my-project",
        uid: "default-po-3e6db",
        name: "default-po-3e6db-opencode",
        namespace: "devpod",
        port: 4096,
        owner_reference: nil
      }

      http_route = DevpodOpencodeOperator.Resources.build_http_route(workspace, @config)

      assert get_in(http_route, ["metadata", "name"]) == "default-po-3e6db-opencode"
      assert get_in(http_route, ["spec", "hostnames"]) == ["default-po-3e6db.devpod.mydomain.com"]

      assert get_in(http_route, ["metadata", "labels", "devpod.sh/workspace-uid"]) ==
               "default-po-3e6db"

      assert get_in(http_route, ["metadata", "labels", "devpod.sh/workspace"]) == "my-project"
    end

    test "includes ownerReferences when owner_reference is set" do
      workspace = %Workspace{
        id: "abc123",
        uid: "abc123",
        name: "abc123-opencode",
        namespace: "devpod",
        port: 4096,
        owner_reference: %{
          "apiVersion" => "v1",
          "kind" => "Pod",
          "name" => "devpod-abc123",
          "uid" => "pod-uid-123"
        }
      }

      http_route = DevpodOpencodeOperator.Resources.build_http_route(workspace, @config)

      assert get_in(http_route, ["metadata", "ownerReferences"]) == [
               %{
                 "apiVersion" => "v1",
                 "kind" => "Pod",
                 "name" => "devpod-abc123",
                 "uid" => "pod-uid-123"
               }
             ]
    end

    test "omits ownerReferences when Pod has no UID" do
      workspace = %Workspace{
        id: "abc123",
        uid: "abc123",
        name: "abc123-opencode",
        namespace: "devpod",
        port: 4096,
        owner_reference: nil
      }

      http_route = DevpodOpencodeOperator.Resources.build_http_route(workspace, @config)

      assert get_in(http_route, ["metadata", "ownerReferences"]) == nil
    end

    test "includes app.kubernetes.io/managed-by label set to devpod-opencode-operator" do
      workspace = %Workspace{
        id: "abc123",
        uid: "abc123",
        name: "abc123-opencode",
        namespace: "devpod",
        port: 4096,
        owner_reference: %{
          "apiVersion" => "v1",
          "kind" => "Pod",
          "name" => "devpod-abc123",
          "uid" => "pod-uid-123"
        }
      }

      http_route = DevpodOpencodeOperator.Resources.build_http_route(workspace, @config)

      assert get_in(http_route, ["metadata", "labels", "app.kubernetes.io/managed-by"]) ==
               "devpod-opencode-operator"
    end

    test "includes devpod.sh/workspace-uid label set to the workspace uid" do
      workspace = %Workspace{
        id: "abc123",
        uid: "abc123",
        name: "abc123-opencode",
        namespace: "devpod",
        port: 4096,
        owner_reference: %{
          "apiVersion" => "v1",
          "kind" => "Pod",
          "name" => "devpod-abc123",
          "uid" => "pod-uid-123"
        }
      }

      http_route = DevpodOpencodeOperator.Resources.build_http_route(workspace, @config)

      assert get_in(http_route, ["metadata", "labels", "devpod.sh/workspace-uid"]) == "abc123"
      assert get_in(http_route, ["metadata", "labels", "devpod.sh/workspace"]) == "abc123"
    end
  end
end
