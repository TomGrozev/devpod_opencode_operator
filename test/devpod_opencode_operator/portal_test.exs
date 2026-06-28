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

  defp build_route(workspace_id, hostname) do
    %{
      "metadata" => %{
        "name" => "#{workspace_id}-opencode",
        "namespace" => @namespace,
        "labels" => %{
          "app.kubernetes.io/managed-by" => "devpod-opencode-operator",
          "devpod.sh/workspace-uid" => workspace_id
        }
      },
      "spec" => %{
        "hostnames" => [hostname]
      }
    }
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
             build_route("abc123", "abc123.example.com")
           ],
           resource_version: "1"
         }}
      end)

      conn = conn(:get, "/")
      conn = Portal.call(conn, Portal.init(namespace: @namespace))

      assert conn.status == 200
      assert conn.resp_body =~ ~s(href="https://abc123.example.com")
      assert conn.resp_body =~ "abc123"
      refute conn.resp_body =~ "No OpenCode Endpoints found."
    end

    test "sorts endpoints by workspace id" do
      DevpodOpencodeOperator.MockK8sCluster
      |> expect(:list_http_routes, fn _conn,
                                      "devpod",
                                      "app.kubernetes.io/managed-by=devpod-opencode-operator" ->
        {:ok,
         %{
           items: [
             build_route("z-id", "z.example.com"),
             build_route("a-id", "a.example.com")
           ],
           resource_version: "1"
         }}
      end)

      conn = conn(:get, "/")
      conn = Portal.call(conn, Portal.init(namespace: @namespace))

      a_pos = :binary.match(conn.resp_body, "a-id") |> elem(0)
      z_pos = :binary.match(conn.resp_body, "z-id") |> elem(0)

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
