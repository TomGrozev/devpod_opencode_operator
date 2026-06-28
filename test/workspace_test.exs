defmodule DevpodOpencodeOperator.WorkspaceTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  alias DevpodOpencodeOperator.Config
  alias DevpodOpencodeOperator.Workspace

  @config %Config{
    target_namespace: "devpod",
    base_domain: "devpod.mydomain.com",
    default_port: 4096,
    gateway_name: "my-gateway",
    gateway_namespace: "gateway-ns"
  }

  defp pod(overrides \\ %{}) do
    Map.merge(
      %{
        "metadata" => %{
          "name" => "devpod-abc123",
          "namespace" => "devpod",
          "uid" => "pod-uid-123",
          "labels" => %{
            "devpod.sh/workspace-uid" => "abc123"
          },
          "annotations" => %{}
        }
      },
      overrides
    )
  end

  defp pod_with_friendly_id(friendly_id, overrides \\ %{}) do
    pod(overrides)
    |> put_in(["spec"], %{
      "containers" => [
        %{
          "name" => "devpod",
          "env" => [
            %{"name" => "DEVPOD_WORKSPACE_ID", "value" => friendly_id}
          ]
        }
      ]
    })
  end

  describe "from_pod/2" do
    test "builds a workspace from a valid pod" do
      {:ok, ws} = Workspace.from_pod(pod(), @config)

      assert ws.id == "abc123"
      assert ws.uid == "abc123"
      assert ws.name == "abc123-opencode"
      assert ws.namespace == "devpod"
      assert ws.port == 4096
    end

    test "reads the friendly id from DEVPOD_WORKSPACE_ID env var when present" do
      {:ok, ws} = Workspace.from_pod(pod_with_friendly_id("my-project"), @config)

      assert ws.id == "my-project"
      assert ws.uid == "abc123"
      assert ws.name == "abc123-opencode"
    end

    test "logs a warning when DEVPOD_WORKSPACE_ID is not set" do
      log =
        capture_log(fn ->
          {:ok, _ws} = Workspace.from_pod(pod(), @config)
        end)

      assert log =~
               "DEVPOD_WORKSPACE_ID not set on devpod container; falling back to workspace-uid as id"
    end

    test "falls back to uid for id when env var is not set" do
      {:ok, ws} = Workspace.from_pod(pod(), @config)

      assert ws.id == ws.uid
    end

    test "returns :error when workspace-uid label is missing" do
      p = pod() |> put_in(["metadata", "labels"], %{})
      assert :error = Workspace.from_pod(p, @config)
    end

    test "returns :error when namespace is missing" do
      p = pod() |> put_in(["metadata", "namespace"], nil)
      assert :error = Workspace.from_pod(p, @config)
    end

    test "sets owner_reference when pod has a uid" do
      {:ok, ws} = Workspace.from_pod(pod(), @config)

      assert ws.owner_reference == %{
               "apiVersion" => "v1",
               "kind" => "Pod",
               "name" => "devpod-abc123",
               "uid" => "pod-uid-123"
             }
    end

    test "sets owner_reference to nil when pod has no uid" do
      p = pod() |> put_in(["metadata", "uid"], nil)
      {:ok, ws} = Workspace.from_pod(p, @config)

      assert ws.owner_reference == nil
    end

    test "sets owner_reference to nil when metadata has no uid key" do
      p =
        pod()
        |> put_in(["metadata"], %{
          "name" => "x",
          "namespace" => "devpod",
          "labels" => %{"devpod.sh/workspace-uid" => "abc123"}
        })

      {:ok, ws} = Workspace.from_pod(p, @config)

      assert ws.owner_reference == nil
    end

    test "uses annotation port when devpod.sh/opencode-port is set" do
      p = pod() |> put_in(["metadata", "annotations", "devpod.sh/opencode-port"], "8080")
      {:ok, ws} = Workspace.from_pod(p, @config)

      assert ws.port == 8080
    end

    test "falls back to config.default_port when annotation is absent" do
      {:ok, ws} = Workspace.from_pod(pod(), @config)

      assert ws.port == 4096
    end

    test "falls back to config.default_port when annotation is not a valid integer" do
      p = pod() |> put_in(["metadata", "annotations", "devpod.sh/opencode-port"], "not-a-number")
      {:ok, ws} = Workspace.from_pod(p, @config)

      assert ws.port == 4096
    end

    test "falls back to config.default_port when annotation has trailing content" do
      p = pod() |> put_in(["metadata", "annotations", "devpod.sh/opencode-port"], "8080abc")
      {:ok, ws} = Workspace.from_pod(p, @config)

      assert ws.port == 4096
    end
  end
end
