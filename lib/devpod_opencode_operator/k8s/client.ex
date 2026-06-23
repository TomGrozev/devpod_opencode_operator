defmodule DevpodOpencodeOperator.K8s.Client do
  @moduledoc """
  Behaviour for the Kubernetes client.

  The real implementation backed by the `k8s` hex package is pending a
  separate issue. The behaviour is defined here so the Reconciler can be
  tested with a fake client.
  """

  @callback apply(module(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback get(module(), String.t(), keyword()) :: {:ok, map() | nil} | {:error, term()}
end
