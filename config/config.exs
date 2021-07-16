# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :media,
  ecto_repos: [Media.Repo]

# Configures the endpoint
config :media, MediaWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "CT7jHPINrjbMscvJaV0ulGFGApqgFgj/z9jPkqIkEmtDtVGOpj0VXPn9ijxAZ7ng",
  render_errors: [view: MediaWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Media.PubSub,
  live_view: [signing_salt: "XkzPx4Yn"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :media,
  otp_app: :your_app,
  active_database: "mongoDB",
  repo: :mongo,
  aws_bucket_name: "your_bucket",
  aws_role_name: "you_role_to_assume_arn",
  ## the IAM user id,
  aws_iam_id: "403016165142",
  content_schema: Blogs.Schema.Article,
  content_table: "blogs"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
