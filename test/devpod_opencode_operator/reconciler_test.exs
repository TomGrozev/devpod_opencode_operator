defmodule DevpodOpencodeOperator.ReconcilerTest do
  use ExUnit.Case
  import ExUnit.CaptureLog
  import Mox

  alias DevpodOpencodeOperator.Config
  alias DevpodOpencodeOperator.Reconciler

  setup :verify_on_exit!

  setup do
    Application.put_env(
      :devpod_opencode_operator,
      :k8s_cluster,
      DevpodOpencodeOperator.MockK8sCluster
    )

    :ok
  end

  @config %Config{
    target_namespace: "devpod",
    base_domain: "example.com",
    default_port: 4096,
    gateway_name: "my-gateway",
    gateway_namespace: "gateway-ns"
  }

  @test_conn %K8s.Conn{url: "https://test-cluster.example.com"}

  defp build_pod(opts) do
    workspace_id = Keyword.get(opts, :workspace_id, "abc123")
    namespace = Keyword.get(opts, :namespace, "devpod")
    annotation_port = Keyword.get(opts, :annotation_port, nil)

    labels = if workspace_id, do: %{"devpod.sh/workspace-uid" => workspace_id}, else: %{}

    annotations =
      case annotation_port do
        nil -> %{}
        port -> %{"devpod.sh/opencode-port" => to_string(port)}
      end

    %{
      "metadata" => %{
        "name" => "devpod-abc123",
        "namespace" => namespace,
        "labels" => labels,
        "annotations" => annotations
      }
    }
  end

  # ===========================================================================
  # Tests
  # ===========================================================================

  describe "reconcile/3 — happy path" do
    test "applies Service and HTTPRoute for a valid pod, returns :ok and logs CREATE" do
      pod = build_pod(workspace_id: "abc123", namespace: "devpod")

      DevpodOpencodeOperator.MockK8sCluster
      |> expect(:get, fn _conn, :Service, name, _opts ->
        assert name == "abc123-opencode"
        {:ok, nil}
      end)
      |> expect(:apply, fn _conn, :Service, name, manifest ->
        assert name == "abc123-opencode"
        assert manifest["kind"] == "Service"
        assert get_in(manifest, ["metadata", "namespace"]) == "devpod"
        {:ok, manifest}
      end)
      |> expect(:apply, fn _conn, :HTTPRoute, name, manifest ->
        assert name == "abc123-opencode"
        assert manifest["kind"] == "HTTPRoute"
        assert get_in(manifest, ["metadata", "namespace"]) == "devpod"
        assert get_in(manifest, ["spec", "hostnames"]) == ["abc123.example.com"]

        parent_refs = get_in(manifest, ["spec", "parentRefs"])
        assert hd(parent_refs)["name"] == "my-gateway"
        assert hd(parent_refs)["namespace"] == "gateway-ns"

        {:ok, manifest}
      end)

      log =
        capture_log(fn ->
          assert :ok = Reconciler.reconcile(@test_conn, pod, @config)
        end)

      assert log =~ "Reconciled workspace: CREATE"
    end
  end

  describe "reconcile/3 — skip path" do
    test "returns {:skipped, :missing_workspace_uid_label} when pod has no workspace-uid label" do
      pod = build_pod(workspace_id: nil)

      # No cluster calls expected — reconcile returns early

      log =
        capture_log(fn ->
          assert {:skipped, :missing_workspace_uid_label} =
                   Reconciler.reconcile(@test_conn, pod, @config)
        end)

      assert log =~ "Skipping pod without"
      assert log =~ "devpod.sh/workspace-uid"
    end
  end

  describe "reconcile/3 — CREATE vs UPDATE" do
    test "logs UPDATE when existing Service has a resourceVersion" do
      pod = build_pod(workspace_id: "abc123", namespace: "devpod")

      DevpodOpencodeOperator.MockK8sCluster
      |> expect(:get, fn _conn, :Service, _name, _opts ->
        {:ok, %{"metadata" => %{"resourceVersion" => "12345"}}}
      end)
      |> expect(:apply, fn _conn, :Service, _name, manifest -> {:ok, manifest} end)
      |> expect(:apply, fn _conn, :HTTPRoute, _name, manifest -> {:ok, manifest} end)

      log =
        capture_log(fn ->
          assert :ok = Reconciler.reconcile(@test_conn, pod, @config)
        end)

      assert log =~ "Reconciled workspace: UPDATE"
    end

    test "logs CREATE when existing Service has nil resourceVersion" do
      pod = build_pod(workspace_id: "abc123", namespace: "devpod")

      DevpodOpencodeOperator.MockK8sCluster
      |> expect(:get, fn _conn, :Service, _name, _opts ->
        {:ok, %{"metadata" => %{"resourceVersion" => nil}}}
      end)
      |> expect(:apply, fn _conn, :Service, _name, manifest -> {:ok, manifest} end)
      |> expect(:apply, fn _conn, :HTTPRoute, _name, manifest -> {:ok, manifest} end)

      log =
        capture_log(fn ->
          assert :ok = Reconciler.reconcile(@test_conn, pod, @config)
        end)

      assert log =~ "Reconciled workspace: CREATE"
    end

    test "logs CREATE when get returns error" do
      pod = build_pod(workspace_id: "abc123", namespace: "devpod")

      DevpodOpencodeOperator.MockK8sCluster
      |> expect(:get, fn _conn, :Service, _name, _opts ->
        {:error, :not_found}
      end)
      |> expect(:apply, fn _conn, :Service, _name, manifest -> {:ok, manifest} end)
      |> expect(:apply, fn _conn, :HTTPRoute, _name, manifest -> {:ok, manifest} end)

      log =
        capture_log(fn ->
          assert :ok = Reconciler.reconcile(@test_conn, pod, @config)
        end)

      assert log =~ "Reconciled workspace: CREATE"
    end
  end

  describe "reconcile/3 — error path" do
    test "returns {:error, reason} when Service apply fails and does not apply HTTPRoute" do
      pod = build_pod(workspace_id: "abc123", namespace: "devpod")

      DevpodOpencodeOperator.MockK8sCluster
      |> expect(:get, fn _conn, :Service, _name, _opts -> {:ok, nil} end)
      |> expect(:apply, fn _conn, :Service, _name, _manifest -> {:error, :forbidden} end)

      # No HTTPRoute apply expectation — the with clause short-circuits

      result = Reconciler.reconcile(@test_conn, pod, @config)
      assert {:error, :forbidden} = result
    end

    test "returns {:error, reason} when HTTPRoute apply fails" do
      pod = build_pod(workspace_id: "abc123", namespace: "devpod")

      DevpodOpencodeOperator.MockK8sCluster
      |> expect(:get, fn _conn, :Service, _name, _opts -> {:ok, nil} end)
      |> expect(:apply, fn _conn, :Service, _name, manifest -> {:ok, manifest} end)
      |> expect(:apply, fn _conn, :HTTPRoute, _name, _manifest ->
        {:error, :route_forbidden}
      end)

      result = Reconciler.reconcile(@test_conn, pod, @config)
      assert {:error, :route_forbidden} = result
    end
  end

  describe "reconcile/3 — port resolution" do
    test "uses annotation port when devpod.sh/opencode-port is set" do
      pod = build_pod(workspace_id: "abc123", annotation_port: "8080")

      DevpodOpencodeOperator.MockK8sCluster
      |> expect(:get, fn _conn, :Service, _name, _opts -> {:ok, nil} end)
      |> expect(:apply, fn _conn, :Service, _name, manifest ->
        assert get_in(manifest, ["spec", "ports", Access.at(0), "targetPort"]) == 8080
        {:ok, manifest}
      end)
      |> expect(:apply, fn _conn, :HTTPRoute, _name, manifest -> {:ok, manifest} end)

      assert :ok = Reconciler.reconcile(@test_conn, pod, @config)
    end

    test "falls back to config.default_port when annotation is absent" do
      pod = build_pod(workspace_id: "abc123", annotation_port: nil)

      DevpodOpencodeOperator.MockK8sCluster
      |> expect(:get, fn _conn, :Service, _name, _opts -> {:ok, nil} end)
      |> expect(:apply, fn _conn, :Service, _name, manifest ->
        assert get_in(manifest, ["spec", "ports", Access.at(0), "targetPort"]) == 4096
        {:ok, manifest}
      end)
      |> expect(:apply, fn _conn, :HTTPRoute, _name, manifest -> {:ok, manifest} end)

      assert :ok = Reconciler.reconcile(@test_conn, pod, @config)
    end
  end
end
