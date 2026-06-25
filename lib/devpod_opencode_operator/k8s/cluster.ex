defmodule DevpodOpencodeOperator.K8s.Cluster do
  @moduledoc """
  Application-boundary behaviour for talking to a Kubernetes cluster.

  This module defines the contract for all Kubernetes operations used by the
  application. Production wires the `:k8s_cluster` application env key to
  `DevpodOpencodeOperator.K8s.Cluster.Live` (which wraps the `k8s` hex
  package); tests wire it to a Mox-generated mock.

  The `list_pods` → `watch_pods` two-phase pattern is the standard
  Kubernetes controller pattern: list to take a snapshot and obtain a
  `resource_version`, then watch for deltas from that point.
  """

  @type conn :: K8s.Conn.t()

  # -------------------------------------------------------------------
  # Callbacks
  # -------------------------------------------------------------------

  @doc "Server-side apply of `manifest` for the resource of kind `kind` named `name`."
  @callback apply(conn, kind :: atom, name :: String.t(), manifest :: map) ::
              {:ok, map} | {:error, term}

  @doc "Fetch a single resource. Returns `{:ok, nil}` when not found (does not error on 404)."
  @callback get(conn, kind :: atom, name :: String.t(), opts :: keyword) ::
              {:ok, map | nil} | {:error, term}

  @doc """
  List pods. Returns atom-keyed `:items` and `:resource_version`.

  The return shape uses `:resource_version` (NOT the raw K8s API server's
  string `metadata.resourceVersion`).
  """
  @callback list_pods(conn, opts :: keyword) ::
              {:ok, %{items: [map], resource_version: String.t() | nil}} | {:error, term}

  @doc "Open a watch stream. `resource_version == nil` means watch from the beginning."
  @callback watch_pods(conn, resource_version :: String.t() | nil, opts :: keyword) ::
              {:ok, Enumerable.t()} | {:error, term}

  # -------------------------------------------------------------------
  # Facade — dispatches to the impl module configured in application env
  # -------------------------------------------------------------------

  defp impl, do: Application.get_env(:devpod_opencode_operator, :k8s_cluster, __MODULE__.Live)

  @spec apply(K8s.Conn.t(), atom, String.t(), map) :: {:ok, map} | {:error, term}
  def apply(conn, kind, name, manifest), do: impl().apply(conn, kind, name, manifest)

  @spec get(K8s.Conn.t(), atom, String.t(), keyword) :: {:ok, map | nil} | {:error, term}
  def get(conn, kind, name, opts), do: impl().get(conn, kind, name, opts)

  @spec list_pods(K8s.Conn.t(), keyword) ::
          {:ok, %{items: [map], resource_version: String.t() | nil}} | {:error, term}
  def list_pods(conn, opts), do: impl().list_pods(conn, opts)

  @spec watch_pods(K8s.Conn.t(), String.t() | nil, keyword) ::
          {:ok, Enumerable.t()} | {:error, term}
  def watch_pods(conn, resource_version, opts),
    do: impl().watch_pods(conn, resource_version, opts)
end
