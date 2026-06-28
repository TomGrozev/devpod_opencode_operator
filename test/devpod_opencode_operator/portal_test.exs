defmodule DevpodOpencodeOperator.PortalTest do
  use ExUnit.Case
  use Plug.Test
  import ExUnit.CaptureLog
  import Mox

  alias DevpodOpencodeOperator.Portal

  @namespace "devpod"
  @label_selector "app.kubernetes.io/managed-by=devpod-opencode-operator"

  @test_conn %K8s.Conn{url: "https://test-cluster.example.com"}

  setup :verify_on_exit!

  setup do
    Application.put_env(
      :devpod_opencode_operator,
      :k8s_cluster,
      DevpodOpencodeOperator.MockK8sCluster
    )

    Mox.set_mox_global()

    {:ok, _} = DevpodOpencodeOperator.K8s.Connection.start_link(conn: @test_conn)

    on_exit(fn ->
      try do
        if Process.whereis(DevpodOpencodeOperator.K8s.Connection) do
          GenServer.stop(DevpodOpencodeOperator.K8s.Connection)
        end
      rescue
        _ -> :ok
      catch
        :exit, _ -> :ok
      end
    end)

    :ok
  end

  defp build_route(workspace_id, hostname, opts \\ []) do
    friendly_id = Keyword.get(opts, :friendly_id)

    labels =
      %{
        "app.kubernetes.io/managed-by" => "devpod-opencode-operator",
        "devpod.sh/workspace-uid" => workspace_id
      }
      |> maybe_add_friendly_label(friendly_id)

    %{
      "metadata" => %{
        "name" => "#{workspace_id}-opencode",
        "namespace" => @namespace,
        "labels" => labels
      },
      "spec" => %{
        "hostnames" => [hostname]
      }
    }
  end

  defp maybe_add_friendly_label(labels, nil), do: labels

  defp maybe_add_friendly_label(labels, friendly_id) do
    Map.put(labels, "devpod.sh/workspace", friendly_id)
  end

  describe "init/1" do
    test "returns the opts unchanged" do
      assert Portal.init(namespace: "devpod") == [namespace: "devpod"]
    end
  end

  describe "call/2 — empty state" do
    test "returns 200 with empty-state message when no routes are listed" do
      DevpodOpencodeOperator.MockK8sCluster
      |> expect(:list_http_routes, fn _conn,
                                      "devpod",
                                      "app.kubernetes.io/managed-by=devpod-opencode-operator" ->
        {:ok, %{items: [], resource_version: "1"}}
      end)

      conn = conn(:get, "/")
      conn = Portal.call(conn, Portal.init(namespace: @namespace))

      assert conn.status == 200
      assert conn.resp_body =~ "No OpenCode Endpoints found."
    end
  end

  describe "call/2 — populated state" do
    test "returns 200 with anchor per route (href from hostname, text from workspace-uid label)" do
      DevpodOpencodeOperator.MockK8sCluster
      |> expect(:list_http_routes, fn _conn,
                                      "devpod",
                                      "app.kubernetes.io/managed-by=devpod-opencode-operator" ->
        {:ok,
         %{
           items: [
             build_route("abc123", "abc123.example.com", friendly_id: "my-project")
           ],
           resource_version: "1"
         }}
      end)

      conn = conn(:get, "/")
      conn = Portal.call(conn, Portal.init(namespace: @namespace))

      assert conn.status == 200
      assert conn.resp_body =~ ~s(href="https://abc123.example.com")
      assert conn.resp_body =~ "my-project"
      refute conn.resp_body =~ "No OpenCode Endpoints found."
    end

    test "prefers devpod.sh/workspace label for display when both are present, and shows the uid as a subline" do
      DevpodOpencodeOperator.MockK8sCluster
      |> expect(:list_http_routes, fn _conn,
                                      "devpod",
                                      "app.kubernetes.io/managed-by=devpod-opencode-operator" ->
        {:ok,
         %{
           items: [
             build_route("default-po-3e6db", "default-po-3e6db.example.com",
               friendly_id: "my-project"
             )
           ],
           resource_version: "1"
         }}
      end)

      conn = conn(:get, "/")
      conn = Portal.call(conn, Portal.init(namespace: @namespace))

      assert conn.status == 200
      assert conn.resp_body =~ "my-project"
      # The main name should be the friendly id, NOT the uid
      refute conn.resp_body =~ ~s(<span class="id">default-po-3e6db</span>)
      # The uid should appear as a subline
      assert conn.resp_body =~ ~s(<span class="uid">default-po-3e6db</span>)
    end

    test "falls back to workspace-uid label for display when devpod.sh/workspace is missing" do
      DevpodOpencodeOperator.MockK8sCluster
      |> expect(:list_http_routes, fn _conn,
                                      "devpod",
                                      "app.kubernetes.io/managed-by=devpod-opencode-operator" ->
        {:ok,
         %{
           items: [
             build_route("abc123", "abc123.example.com")
           ],
           resource_version: "1"
         }}
      end)

      conn = conn(:get, "/")
      conn = Portal.call(conn, Portal.init(namespace: @namespace))

      assert conn.status == 200
      assert conn.resp_body =~ "abc123"
    end

    test "omits the uid subline when friendly id and uid are identical" do
      DevpodOpencodeOperator.MockK8sCluster
      |> expect(:list_http_routes, fn _conn,
                                      "devpod",
                                      "app.kubernetes.io/managed-by=devpod-opencode-operator" ->
        {:ok,
         %{
           items: [
             # friendly_id is the same as the uid — no subline should render
             build_route("abc123", "abc123.example.com", friendly_id: "abc123")
           ],
           resource_version: "1"
         }}
      end)

      conn = conn(:get, "/")
      conn = Portal.call(conn, Portal.init(namespace: @namespace))

      assert conn.status == 200
      # The id is shown (using the friendly_id, which equals the uid)
      assert conn.resp_body =~ ~s(<span class="id">abc123</span>)
      # No subline is rendered because they are identical
      refute conn.resp_body =~ ~s(<span class="uid">)
    end

    test "shows only the uid (no subline) when the friendly label is missing" do
      DevpodOpencodeOperator.MockK8sCluster
      |> expect(:list_http_routes, fn _conn,
                                      "devpod",
                                      "app.kubernetes.io/managed-by=devpod-opencode-operator" ->
        {:ok,
         %{
           items: [
             # No friendly_id option — only the workspace-uid label
             build_route("abc123", "abc123.example.com")
           ],
           resource_version: "1"
         }}
      end)

      conn = conn(:get, "/")
      conn = Portal.call(conn, Portal.init(namespace: @namespace))

      assert conn.status == 200
      # The id is shown (falls back to uid)
      assert conn.resp_body =~ ~s(<span class="id">abc123</span>)
      # No subline because there's no separate friendly id
      refute conn.resp_body =~ ~s(<span class="uid">)
    end

    test "sorts endpoints by workspace id" do
      DevpodOpencodeOperator.MockK8sCluster
      |> expect(:list_http_routes, fn _conn,
                                      "devpod",
                                      "app.kubernetes.io/managed-by=devpod-opencode-operator" ->
        {:ok,
         %{
           items: [
             build_route("z-id", "z.example.com", friendly_id: "z-project"),
             build_route("a-id", "a.example.com", friendly_id: "a-project")
           ],
           resource_version: "1"
         }}
      end)

      conn = conn(:get, "/")
      conn = Portal.call(conn, Portal.init(namespace: @namespace))

      a_pos = :binary.match(conn.resp_body, "a-project") |> elem(0)
      z_pos = :binary.match(conn.resp_body, "z-project") |> elem(0)

      assert a_pos < z_pos
    end

    test "skips routes that lack the devpod.sh/workspace-uid label" do
      orphan_route = %{
        "metadata" => %{
          "name" => "orphan",
          "namespace" => @namespace,
          "labels" => %{
            "app.kubernetes.io/managed-by" => "devpod-opencode-operator"
          }
        },
        "spec" => %{"hostnames" => ["orphan.example.com"]}
      }

      DevpodOpencodeOperator.MockK8sCluster
      |> expect(:list_http_routes, fn _conn,
                                      "devpod",
                                      "app.kubernetes.io/managed-by=devpod-opencode-operator" ->
        {:ok,
         %{
           items: [
             build_route("abc123", "abc123.example.com"),
             orphan_route
           ],
           resource_version: "1"
         }}
      end)

      conn = conn(:get, "/")
      conn = Portal.call(conn, Portal.init(namespace: @namespace))

      assert conn.status == 200
      assert conn.resp_body =~ "abc123"
      refute conn.resp_body =~ "orphan.example.com"
    end

    test "returns Content-Type: text/html" do
      DevpodOpencodeOperator.MockK8sCluster
      |> expect(:list_http_routes, fn _conn,
                                      "devpod",
                                      "app.kubernetes.io/managed-by=devpod-opencode-operator" ->
        {:ok, %{items: [], resource_version: "1"}}
      end)

      conn = conn(:get, "/")
      conn = Portal.call(conn, Portal.init(namespace: @namespace))

      assert Plug.Conn.get_resp_header(conn, "content-type") |> hd() =~ "text/html"
    end
  end

  describe "call/2 — error state" do
    test "returns 500 with minimal HTML body on list error, logs warning" do
      DevpodOpencodeOperator.MockK8sCluster
      |> expect(:list_http_routes, fn _conn,
                                      "devpod",
                                      "app.kubernetes.io/managed-by=devpod-opencode-operator" ->
        {:error, :forbidden}
      end)

      log =
        capture_log(fn ->
          conn = conn(:get, "/")
          conn = Portal.call(conn, Portal.init(namespace: @namespace))

          assert conn.status == 500
          assert conn.resp_body =~ "Portal unavailable:"
          refute conn.resp_body =~ ":forbidden"
        end)

      assert log =~ "Portal failed to list HTTPRoutes"
      assert log =~ ":forbidden"
    end
  end
end
