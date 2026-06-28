defmodule DevpodOpencodeOperator.MixProject do
  use Mix.Project

  def project do
    [
      app: :devpod_opencode_operator,
      version: "0.2.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod:
        if(Mix.env() != :test,
          do: {DevpodOpencodeOperator.Application, []},
          else: []
        ),
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:k8s, "~> 2.8"},
      {:plug, "~> 1.16"},
      {:bandit, "~> 1.6"},
      {:mox, "~> 1.0", only: :test}
    ]
  end
end
