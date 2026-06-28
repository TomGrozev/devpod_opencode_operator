defmodule DevpodOpencodeOperator.ConfigTest do
  use ExUnit.Case

  @required_env %{
    "BASE_DOMAIN" => "example.com",
    "GATEWAY_NAME" => "my-gateway",
    "GATEWAY_NAMESPACE" => "gateway-ns",
    "TARGET_NAMESPACE" => "custom-ns",
    "DEFAULT_PORT" => "8080",
    "PORTAL_PORT" => "4000"
  }

  setup do
    Enum.each(@required_env, fn {k, v} -> System.put_env(k, v) end)

    on_exit(fn ->
      Enum.each(@required_env, fn {k, _} -> System.delete_env(k) end)
    end)
  end

  describe "load/0" do
    test "returns a complete config struct when all env vars are present" do
      config = DevpodOpencodeOperator.Config.load()

      assert config.base_domain == "example.com"
      assert config.gateway_name == "my-gateway"
      assert config.gateway_namespace == "gateway-ns"
      assert config.target_namespace == "custom-ns"
      assert config.default_port == 8080
    end

    test "uses default target namespace when TARGET_NAMESPACE is not set" do
      System.delete_env("TARGET_NAMESPACE")

      config = DevpodOpencodeOperator.Config.load()

      assert config.target_namespace == "devpod"
    end

    test "uses default port when DEFAULT_PORT is not set" do
      System.delete_env("DEFAULT_PORT")

      config = DevpodOpencodeOperator.Config.load()

      assert config.default_port == 4096
    end

    test "raises when BASE_DOMAIN is missing" do
      System.delete_env("BASE_DOMAIN")

      error = assert_raise RuntimeError, fn -> DevpodOpencodeOperator.Config.load() end
      assert error.message =~ "BASE_DOMAIN"
    end

    test "raises when GATEWAY_NAME is missing" do
      System.delete_env("GATEWAY_NAME")

      error = assert_raise RuntimeError, fn -> DevpodOpencodeOperator.Config.load() end
      assert error.message =~ "GATEWAY_NAME"
    end

    test "raises when GATEWAY_NAMESPACE is missing" do
      System.delete_env("GATEWAY_NAMESPACE")

      error = assert_raise RuntimeError, fn -> DevpodOpencodeOperator.Config.load() end
      assert error.message =~ "GATEWAY_NAMESPACE"
    end

    test "raises when DEFAULT_PORT is not a valid integer" do
      System.put_env("DEFAULT_PORT", "notanumber")

      error = assert_raise ArgumentError, fn -> DevpodOpencodeOperator.Config.load() end
      assert error.message =~ "DEFAULT_PORT"
      assert error.message =~ "integer"
    end

    test "raises when DEFAULT_PORT is below valid range" do
      System.put_env("DEFAULT_PORT", "0")

      error = assert_raise ArgumentError, fn -> DevpodOpencodeOperator.Config.load() end
      assert error.message =~ "DEFAULT_PORT"
      assert error.message =~ "between 1 and 65535"
    end

    test "raises when DEFAULT_PORT is above valid range" do
      System.put_env("DEFAULT_PORT", "70000")

      error = assert_raise ArgumentError, fn -> DevpodOpencodeOperator.Config.load() end
      assert error.message =~ "DEFAULT_PORT"
      assert error.message =~ "between 1 and 65535"
    end

    test "uses default portal port 4000 when PORTAL_PORT is not set" do
      System.delete_env("PORTAL_PORT")
      config = DevpodOpencodeOperator.Config.load()
      assert config.portal_port == 4000
    end

    test "parses PORTAL_PORT from env when set" do
      System.put_env("PORTAL_PORT", "9090")
      config = DevpodOpencodeOperator.Config.load()
      assert config.portal_port == 9090
    end
  end
end
