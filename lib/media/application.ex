defmodule Media.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias Media.Helpers

  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      # Start the Telemetry supervisor
      MediaWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Media.PubSub},
      # Start the Endpoint (http/https)
      MediaWeb.Endpoint
      # Start a worker by calling: Media.Worker.start_link(arg)
      # {Media.Worker, arg}
    ]

    children =
      if System.get_env("MEDIA_TEST") == "test" do
        databases = [
          {Mongo,
           [
             name: :mongo,
             hostname: Application.get_env(:media, :db)[:mongo_url],
             database: Application.get_env(:media, :db)[:database],
             port: Application.get_env(:media, :db)[:port],
             username: Application.get_env(:media, :db)[:mongo_user],
             password: Application.get_env(:media, :db)[:mongo_passwd],
             ssl: Application.get_env(:media, :db)[:mongo_ssl],
             pool_size: Application.get_env(:media, :db)[:pool_size]
           ]},
          Media.Repo,
          {Task, fn -> Helpers.create_collections() end}
        ]

        children ++ databases
      else
        children
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Media.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    MediaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
