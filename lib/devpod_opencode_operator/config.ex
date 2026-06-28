defmodule DevpodOpencodeOperator.Config do
  @moduledoc """
  Loads and validates runtime configuration from environment variables.
  """

  defstruct target_namespace: "devpod",
            base_domain: nil,
            default_port: 4096,
            portal_port: 4000,
            gateway_name: nil,
            gateway_namespace: nil

  @type t :: %__MODULE__{
          target_namespace: String.t(),
          base_domain: String.t(),
          default_port: 0..65535,
          portal_port: 0..65535,
          gateway_name: String.t(),
          gateway_namespace: String.t()
        }

  @spec load() :: t() | no_return()
  def load do
    %__MODULE__{
      base_domain: require_env!("BASE_DOMAIN"),
      gateway_name: require_env!("GATEWAY_NAME"),
      gateway_namespace: require_env!("GATEWAY_NAMESPACE"),
      target_namespace: System.get_env("TARGET_NAMESPACE") || "devpod",
      default_port: parse_port(System.get_env("DEFAULT_PORT") || "4096"),
      portal_port: parse_port(System.get_env("PORTAL_PORT") || "4000")
    }
  end

  defp require_env!(name) do
    case System.get_env(name) do
      nil -> raise "#{name} environment variable is required"
      value -> value
    end
  end

  defp parse_port(raw, env_name \\ "DEFAULT_PORT") do
    case Integer.parse(raw) do
      {port, ""} when port in 1..65535 ->
        port

      {port, ""} ->
        raise ArgumentError, "#{env_name} must be between 1 and 65535, got: #{port}"

      _ ->
        raise ArgumentError, "#{env_name} must be a valid integer, got: #{inspect(raw)}"
    end
  end
end
