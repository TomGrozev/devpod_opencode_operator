defmodule DevpodOpencodeOperator.K8s.Production do
  @moduledoc """
  Production Kubernetes cluster client implementing `DevpodOpencodeOperator.K8s`.

  Wraps the `k8s` hex package to perform real Kubernetes API operations.
  This module does NOT create the connection — the caller passes a
  `K8s.Conn.t()` constructed elsewhere (typically in the Application module).
  """

  @behaviour DevpodOpencodeOperator.K8s

  require Logger

  # Map atom kind names to {apiVersion, kind} tuples
  @api_versions %{
    Service: {"v1", "Service"},
    HTTPRoute: {"gateway.networking.k8s.io/v1", "HTTPRoute"},
    Pod: {"v1", "Pod"}
  }

  # -------------------------------------------------------------------
  # Callbacks
  # -------------------------------------------------------------------

  @impl true
  def apply(conn, _kind, _name, manifest) do
    op = K8s.Client.apply(manifest, field_manager: "devpod-opencode-operator", force: true)
    K8s.Client.run(conn, op)
  end

  @impl true
  def get(conn, kind, name, opts) do
    {api_version, kind_str} = resolve_api_version(kind)
    op = K8s.Client.get(api_version, kind_str, opts ++ [name: name])

    case K8s.Client.run(conn, op) do
      {:ok, resource} ->
        {:ok, resource}

      {:error, %K8s.Client.APIError{reason: "NotFound"}} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def list_pods(conn, opts) do
    {api_version, kind_str} = resolve_api_version(:Pod)
    op = K8s.Client.list(api_version, kind_str, opts)

    case K8s.Client.run(conn, op) do
      {:ok, response} ->
        items = Map.get(response, "items", [])

        resource_version =
          case response do
            %{"metadata" => %{"resourceVersion" => rv}} when is_binary(rv) -> rv
            _ -> derive_resource_version(items)
          end

        {:ok, %{items: items, resource_version: resource_version}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def watch_pods(conn, resource_version, opts) do
    {api_version, kind_str} = resolve_api_version(:Pod)

    watch_opts =
      if resource_version do
        opts ++ [resourceVersion: resource_version]
      else
        opts
      end

    op = K8s.Client.watch(api_version, kind_str, watch_opts)
    K8s.Client.stream(conn, op)
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  defp resolve_api_version(kind) when is_atom(kind) do
    case @api_versions[kind] do
      nil -> raise ArgumentError, "Unknown kind: #{inspect(kind)}. Add it to @api_versions."
      pair -> pair
    end
  end

  defp resolve_api_version(kind) when is_binary(kind) do
    {"v1", kind}
  end

  defp derive_resource_version(items) do
    items
    |> Enum.map(fn item ->
      get_in(item, ["metadata", "resourceVersion"])
    end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      versions -> Enum.max(versions)
    end
  end
end
