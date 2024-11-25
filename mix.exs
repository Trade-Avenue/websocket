defmodule Websocket.MixProject do
  use Mix.Project

  def project do
    [
      app: :websocket,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:gun, "~> 2.1.0"},
      {:typedstruct, "~> 0.5"}
    ]
  end
end
