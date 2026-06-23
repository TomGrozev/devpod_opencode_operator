defmodule DevpodOpencodeOperator.ReconcilerTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  alias DevpodOpencodeOperator.Config
  alias DevpodOpencodeOperator.Reconciler

  @config %Config{
    target_namespace: "devpod",
    base_domain: "example.com",
    default_port: 4096,
    gateway_name: "my-gateway",
    gateway_namespace: "gateway-ns"
  }

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

  # ---------------------------------------------------------------------------
  # Configurable fake client — records apply calls, configurable get + apply
  # ---------------------------------------------------------------------------

  # NOTE: Uses a globally-named Agent. Safe because the test module runs
  # synchronously (no `async: true`). Do not enable async without restructuring.
  defmodule TrackingFakeClient do
    @moduledoc false
    use Agent

    def start_link do
      # Stop any previous instance first
      try do
        Agent.stop(__MODULE__, :normal, 100)
      catch
        :exit, _ -> :ok
      end

      Agent.start_link(
        fn -> %{calls: [], get_response: {:ok, nil}, apply_response: nil} end,
        name: __MODULE__
      )
    end

    def get(_mod, _name, _opts) do
      Agent.get(__MODULE__, fn state -> state.get_response end)
    end

    def set_get_response(response) do
      Agent.update(__MODULE__, fn state -> %{state | get_response: response} end)
    end

    def apply(mod, name, manifest) do
      Agent.update(__MODULE__, fn state ->
        %{state | calls: [{:apply, mod, name, manifest} | state.calls]}
      end)

      Agent.get(__MODULE__, fn
        %{apply_response: nil} -> {:ok, manifest}
        %{apply_response: resp} -> resp
      end)
    end

    def set_apply_response(response) do
      Agent.update(__MODULE__, fn state -> %{state | apply_response: response} end)
    end

    def pop_calls do
      state = Agent.get(__MODULE__, fn s -> s end)
      calls = Enum.reverse(state.calls)
      Agent.update(__MODULE__, fn s -> %{s | calls: []} end)
      calls
    end
  end

  # ---------------------------------------------------------------------------
  # Fake client that succeeds on Service but fails on HTTPRoute
  # ---------------------------------------------------------------------------

  # NOTE: Uses a globally-named Agent. Safe because the test module runs
  # synchronously (no `async: true`). Do not enable async without restructuring.
  defmodule RouteFailClient do
    @moduledoc false
    use Agent

    def start_link do
      try do
        Agent.stop(__MODULE__, :normal, 100)
      catch
        :exit, _ -> :ok
      end

      Agent.start_link(fn -> %{calls: []} end, name: __MODULE__)
    end

    def get(_mod, _name, _opts), do: {:ok, nil}

    def apply(:Service, name, manifest) do
      Agent.update(__MODULE__, fn state ->
        %{state | calls: [{:apply, :Service, name, manifest} | state.calls]}
      end)

      {:ok, manifest}
    end

    def apply(:HTTPRoute, name, manifest) do
      Agent.update(__MODULE__, fn state ->
        %{state | calls: [{:apply, :HTTPRoute, name, manifest} | state.calls]}
      end)

      {:error, :route_forbidden}
    end

    def pop_calls do
      state = Agent.get(__MODULE__, fn s -> s end)
      calls = Enum.reverse(state.calls)
      Agent.update(__MODULE__, fn s -> %{s | calls: []} end)
      calls
    end
  end

  # ===========================================================================
  # Tests
  # ===========================================================================

  describe "reconcile/3 — happy path" do
    test "applies Service and HTTPRoute for a valid pod, returns :ok and logs CREATE" do
      TrackingFakeClient.start_link()

      pod = build_pod(workspace_id: "abc123", namespace: "devpod")

      log =
        capture_log(fn ->
          assert :ok = Reconciler.reconcile(pod, @config, TrackingFakeClient)
        end)

      assert log =~ "Reconciled workspace: CREATE"

      calls = TrackingFakeClient.pop_calls()
      assert length(calls) == 2

      [service_call, route_call] = calls

      # Service call
      assert {:apply, :Service, "abc123-opencode", service_manifest} = service_call
      assert service_manifest["kind"] == "Service"
      assert get_in(service_manifest, ["metadata", "namespace"]) == "devpod"

      # HTTPRoute call
      assert {:apply, :HTTPRoute, "abc123-opencode", route_manifest} = route_call
      assert route_manifest["kind"] == "HTTPRoute"
      assert get_in(route_manifest, ["metadata", "namespace"]) == "devpod"
      assert get_in(route_manifest, ["spec", "hostnames"]) == ["abc123.example.com"]

      parent_refs = get_in(route_manifest, ["spec", "parentRefs"])
      assert hd(parent_refs)["name"] == "my-gateway"
      assert hd(parent_refs)["namespace"] == "gateway-ns"
    end
  end

  describe "reconcile/3 — skip path" do
    test "returns {:skipped, :missing_workspace_uid_label} when pod has no workspace-uid label" do
      TrackingFakeClient.start_link()

      pod = build_pod(workspace_id: nil)

      log =
        capture_log(fn ->
          assert {:skipped, :missing_workspace_uid_label} =
                   Reconciler.reconcile(pod, @config, TrackingFakeClient)
        end)

      assert log =~ "Skipping pod without"
      assert log =~ "devpod.sh/workspace-uid"

      calls = TrackingFakeClient.pop_calls()
      assert calls == []
    end
  end

  describe "reconcile/3 — CREATE vs UPDATE" do
    test "logs UPDATE when existing Service has a resourceVersion" do
      TrackingFakeClient.start_link()

      TrackingFakeClient.set_get_response({:ok, %{"metadata" => %{"resourceVersion" => "12345"}}})

      pod = build_pod(workspace_id: "abc123", namespace: "devpod")

      log =
        capture_log(fn ->
          assert :ok = Reconciler.reconcile(pod, @config, TrackingFakeClient)
        end)

      assert log =~ "Reconciled workspace: UPDATE"
    end

    test "logs CREATE when existing Service has nil resourceVersion" do
      TrackingFakeClient.start_link()

      TrackingFakeClient.set_get_response({:ok, %{"metadata" => %{"resourceVersion" => nil}}})

      pod = build_pod(workspace_id: "abc123", namespace: "devpod")

      log =
        capture_log(fn ->
          assert :ok = Reconciler.reconcile(pod, @config, TrackingFakeClient)
        end)

      assert log =~ "Reconciled workspace: CREATE"
    end

    test "logs CREATE when get returns error" do
      TrackingFakeClient.start_link()
      TrackingFakeClient.set_get_response({:error, :not_found})

      pod = build_pod(workspace_id: "abc123", namespace: "devpod")

      log =
        capture_log(fn ->
          assert :ok = Reconciler.reconcile(pod, @config, TrackingFakeClient)
        end)

      assert log =~ "Reconciled workspace: CREATE"
    end
  end

  describe "reconcile/3 — error path" do
    test "returns {:error, reason} when Service apply fails and does not apply HTTPRoute" do
      TrackingFakeClient.start_link()
      TrackingFakeClient.set_apply_response({:error, :forbidden})

      pod = build_pod(workspace_id: "abc123", namespace: "devpod")

      result = Reconciler.reconcile(pod, @config, TrackingFakeClient)

      assert {:error, :forbidden} = result

      calls = TrackingFakeClient.pop_calls()

      # Only the Service apply should have been attempted
      service_calls = Enum.filter(calls, fn {:apply, kind, _, _} -> kind == :Service end)
      route_calls = Enum.filter(calls, fn {:apply, kind, _, _} -> kind == :HTTPRoute end)

      assert length(service_calls) == 1
      assert length(route_calls) == 0
    end

    test "returns {:error, reason} when HTTPRoute apply fails" do
      RouteFailClient.start_link()

      pod = build_pod(workspace_id: "abc123", namespace: "devpod")

      result = Reconciler.reconcile(pod, @config, RouteFailClient)

      assert {:error, :route_forbidden} = result

      calls = RouteFailClient.pop_calls()
      service_calls = Enum.filter(calls, fn {:apply, kind, _, _} -> kind == :Service end)
      route_calls = Enum.filter(calls, fn {:apply, kind, _, _} -> kind == :HTTPRoute end)

      assert length(service_calls) == 1
      assert length(route_calls) == 1
    end
  end

  describe "reconcile/3 — port resolution" do
    test "uses annotation port when devpod.sh/opencode-port is set" do
      TrackingFakeClient.start_link()

      pod = build_pod(workspace_id: "abc123", annotation_port: "8080")

      assert :ok = Reconciler.reconcile(pod, @config, TrackingFakeClient)

      calls = TrackingFakeClient.pop_calls()

      {:apply, :Service, _name, service_manifest} =
        Enum.find(calls, fn {:apply, kind, _, _} -> kind == :Service end)

      assert get_in(service_manifest, ["spec", "ports", Access.at(0), "targetPort"]) == 8080
    end

    test "falls back to config.default_port when annotation is absent" do
      TrackingFakeClient.start_link()

      pod = build_pod(workspace_id: "abc123", annotation_port: nil)

      assert :ok = Reconciler.reconcile(pod, @config, TrackingFakeClient)

      calls = TrackingFakeClient.pop_calls()

      {:apply, :Service, _name, service_manifest} =
        Enum.find(calls, fn {:apply, kind, _, _} -> kind == :Service end)

      assert get_in(service_manifest, ["spec", "ports", Access.at(0), "targetPort"]) == 4096
    end
  end
end
