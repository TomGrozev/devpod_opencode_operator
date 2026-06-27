defmodule DevpodOpencodeOperator.WatcherTest do
  use ExUnit.Case
  import ExUnit.CaptureLog
  import Mox

  alias DevpodOpencodeOperator.Config
  alias DevpodOpencodeOperator.Watcher

  setup :verify_on_exit!

  setup do
    Application.put_env(
      :devpod_opencode_operator,
      :k8s_cluster,
      DevpodOpencodeOperator.MockK8sCluster
    )

    Mox.set_mox_global()
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

  # ---------------------------------------------------------------------------
  # Helper to build a pod map (string keys, K8s API shape)
  # ---------------------------------------------------------------------------

  defp build_pod(opts) do
    workspace_id = Keyword.get(opts, :workspace_id, "abc123")
    namespace = Keyword.get(opts, :namespace, "devpod")
    rv = Keyword.get(opts, :resource_version, "100")

    %{
      "metadata" => %{
        "name" => "devpod-#{workspace_id}",
        "namespace" => namespace,
        "resourceVersion" => rv,
        "labels" => %{
          "devpod.sh/workspace-uid" => workspace_id
        }
      }
    }
  end

  # ---------------------------------------------------------------------------
  # Stub helpers — global stubs for calls made inside the GenServer process.
  # Individual tests configure responses via process dictionary or agent state.
  # ---------------------------------------------------------------------------

  defp stub_reconcile_success do
    stub(DevpodOpencodeOperator.MockK8sCluster, :apply, fn _conn, _kind, _name, manifest ->
      {:ok, manifest}
    end)
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "init/1 — list-then-watch" do
    test "calls list_pods on startup" do
      pod = build_pod(workspace_id: "ws1")
      stub_reconcile_success()

      stub(DevpodOpencodeOperator.MockK8sCluster, :list_pods, fn _conn, _opts ->
        {:ok, %{items: [pod], resource_version: "42"}}
      end)

      stub(DevpodOpencodeOperator.MockK8sCluster, :watch_pods, fn _conn, _rv, _opts ->
        {:ok, []}
      end)

      {:ok, _pid} =
        Watcher.start_link(
          config: @config,
          conn: @test_conn,
          backoff: 50
        )

      Process.sleep(100)
    end

    test "reconciles each pod from the list" do
      pod1 = build_pod(workspace_id: "ws1")
      pod2 = build_pod(workspace_id: "ws2")
      stub_reconcile_success()

      stub(DevpodOpencodeOperator.MockK8sCluster, :list_pods, fn _conn, _opts ->
        {:ok, %{items: [pod1, pod2], resource_version: "42"}}
      end)

      stub(DevpodOpencodeOperator.MockK8sCluster, :watch_pods, fn _conn, _rv, _opts ->
        {:ok, []}
      end)

      log =
        capture_log(fn ->
          {:ok, _pid} =
            Watcher.start_link(
              config: @config,
              conn: @test_conn,
              backoff: 50
            )

          Process.sleep(100)
        end)

      assert log =~ "Reconciled workspace"
    end

    test "uses list resourceVersion for watch_pods call" do
      pod = build_pod(workspace_id: "ws1", resource_version: "99")
      stub_reconcile_success()

      {:ok, watch_rv_ref} = Agent.start_link(fn -> [] end)

      stub(DevpodOpencodeOperator.MockK8sCluster, :list_pods, fn _conn, _opts ->
        {:ok, %{items: [pod], resource_version: "42"}}
      end)

      stub(DevpodOpencodeOperator.MockK8sCluster, :watch_pods, fn _conn, rv, _opts ->
        Agent.update(watch_rv_ref, fn acc -> [rv | acc] end)
        {:ok, []}
      end)

      {:ok, _pid} =
        Watcher.start_link(
          config: @config,
          conn: @test_conn,
          backoff: 50
        )

      Process.sleep(100)

      all_rvs = Agent.get(watch_rv_ref, & &1)
      assert "42" in all_rvs
    end
  end

  describe "watch event handling" do
    test "ADDED event reconciles the pod" do
      event = %{
        "type" => "ADDED",
        "object" => build_pod(workspace_id: "ws1", resource_version: "101")
      }

      stub_reconcile_success()

      stub(DevpodOpencodeOperator.MockK8sCluster, :list_pods, fn _conn, _opts ->
        {:ok, %{items: [], resource_version: "0"}}
      end)

      stub(DevpodOpencodeOperator.MockK8sCluster, :watch_pods, fn _conn, _rv, _opts ->
        {:ok, [event]}
      end)

      log =
        capture_log(fn ->
          {:ok, _pid} =
            Watcher.start_link(
              config: @config,
              conn: @test_conn,
              backoff: 50
            )

          Process.sleep(100)
        end)

      assert log =~ "Reconciled workspace"
    end

    test "MODIFIED event reconciles the pod" do
      event = %{
        "type" => "MODIFIED",
        "object" => build_pod(workspace_id: "ws2", resource_version: "102")
      }

      stub_reconcile_success()

      stub(DevpodOpencodeOperator.MockK8sCluster, :list_pods, fn _conn, _opts ->
        {:ok, %{items: [], resource_version: "0"}}
      end)

      stub(DevpodOpencodeOperator.MockK8sCluster, :watch_pods, fn _conn, _rv, _opts ->
        {:ok, [event]}
      end)

      log =
        capture_log(fn ->
          {:ok, _pid} =
            Watcher.start_link(
              config: @config,
              conn: @test_conn,
              backoff: 50
            )

          Process.sleep(100)
        end)

      assert log =~ "Reconciled workspace"
    end

    test "DELETED event does NOT call reconcile" do
      event = %{
        "type" => "DELETED",
        "object" => build_pod(workspace_id: "ws3", resource_version: "103")
      }

      # No reconcile stubs needed — DELETED events don't trigger reconcile

      stub(DevpodOpencodeOperator.MockK8sCluster, :list_pods, fn _conn, _opts ->
        {:ok, %{items: [], resource_version: "0"}}
      end)

      stub(DevpodOpencodeOperator.MockK8sCluster, :watch_pods, fn _conn, _rv, _opts ->
        {:ok, [event]}
      end)

      log =
        capture_log(fn ->
          {:ok, _pid} =
            Watcher.start_link(
              config: @config,
              conn: @test_conn,
              backoff: 50
            )

          Process.sleep(100)
        end)

      refute log =~ "Reconciled workspace"
      assert log =~ "Pod deleted: devpod-ws3"
    end

    test "updates resourceVersion from events for watch resume" do
      event = %{
        "type" => "ADDED",
        "object" => build_pod(workspace_id: "ws1", resource_version: "200")
      }

      stub_reconcile_success()

      {:ok, watch_calls_ref} =
        :ets.new(:watch_calls, [:public, :bag]) |> then(fn t -> {:ok, t} end)

      stub(DevpodOpencodeOperator.MockK8sCluster, :list_pods, fn _conn, _opts ->
        {:ok, %{items: [], resource_version: "0"}}
      end)

      stub(DevpodOpencodeOperator.MockK8sCluster, :watch_pods, fn _conn, rv, _opts ->
        :ets.insert(watch_calls_ref, {rv})

        if rv == "0" do
          {:ok, [event]}
        else
          {:ok, []}
        end
      end)

      {:ok, _pid} =
        Watcher.start_link(
          config: @config,
          conn: @test_conn,
          backoff: 50
        )

      # Wait long enough for:
      # 1. list (0ms) + watch (0ms) + stream ends + reconnect scheduled at 1000ms (after list success resets backoff)
      # 2. second watch at ~1000ms
      Process.sleep(1500)

      all = :ets.tab2list(watch_calls_ref) |> Enum.map(fn {rv} -> rv end)
      assert "0" in all
      assert "200" in all
    end
  end

  describe "error handling" do
    test "retries list_pods on error" do
      {:ok, call_count_ref} = Agent.start_link(fn -> 0 end)

      stub(DevpodOpencodeOperator.MockK8sCluster, :list_pods, fn _conn, _opts ->
        Agent.update(call_count_ref, &(&1 + 1))
        {:error, :timeout}
      end)

      log =
        capture_log(fn ->
          {:ok, _pid} =
            Watcher.start_link(
              config: @config,
              conn: @test_conn,
              backoff: 50
            )

          Process.sleep(200)
        end)

      assert log =~ "Failed to list pods"
      assert log =~ ":timeout"
    end

    test "backoff doubles on consecutive failures" do
      stub(DevpodOpencodeOperator.MockK8sCluster, :list_pods, fn _conn, _opts ->
        {:error, :timeout}
      end)

      log =
        capture_log(fn ->
          {:ok, _pid} =
            Watcher.start_link(
              config: @config,
              conn: @test_conn,
              backoff: 50
            )

          Process.sleep(300)
        end)

      assert log =~ "retrying in 50ms"
      assert log =~ "retrying in 100ms"
    end

    test "retries watch on stream error" do
      pod = build_pod(workspace_id: "ws1")
      stub_reconcile_success()

      {:ok, call_count_ref} = Agent.start_link(fn -> 0 end)

      stub(DevpodOpencodeOperator.MockK8sCluster, :list_pods, fn _conn, _opts ->
        {:ok, %{items: [pod], resource_version: "42"}}
      end)

      stub(DevpodOpencodeOperator.MockK8sCluster, :watch_pods, fn _conn, _rv, _opts ->
        count = Agent.get(call_count_ref, & &1)
        Agent.update(call_count_ref, &(&1 + 1))

        if count == 0 do
          {:error, :watch_timeout}
        else
          {:ok, []}
        end
      end)

      log =
        capture_log(fn ->
          {:ok, _pid} =
            Watcher.start_link(
              config: @config,
              conn: @test_conn,
              backoff: 50
            )

          Process.sleep(200)
        end)

      assert log =~ "Failed to open watch stream"
      assert log =~ ":watch_timeout"
    end
  end
end
