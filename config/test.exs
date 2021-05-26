use Mix.Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.

## POSTGRESQL TEST DB

# Configure your database
config :media, Media.Repo,
  after_connect: {Postgrex, :query!, ["SET search_path TO media,public", []]},
  username: "testing",
  password: "testing",
  database: "test",
  hostname: "postgre.eweev.rocks",
  pool: Ecto.Adapters.SQL.Sandbox,
  ownership_timeout: 60_000,
  queue_target: 1_000,
  queue_interval: 5_000

## MONGO TEST DB
config :media, :db,
  mongo_url: "mongodb.eweev.rocks",
  database: "media_test",
  mongo_ssl: false,
  port: 8017,
  pool_size: 2

## INITIALLY THE REPO SHOULD POINT TO
## MONGO DB SETUP for project inlcuding media as a dep
config :media,
  otp_app: :your_app,
  active_database: "mongoDB",
  repo: :mongo,
  router: Media.TestWeb.Router,
  aws_bucket_name: "eweevtestbucketprivate",
  aws_role_name: "privateBucketRead",
  aws_iam_id: "403016165142"

# content_schema: Sections.Section.Type

# ## POSTGRESQL SETUP
config :media,
  # otp_app: :blogs,
  active_database: "postgreSQL",
  # repo: Media.Repo,
  router: Media.TestWeb.Router,
  aws_bucket_name: "eweevtestbucketprivate",
  aws_role_name: "privateBucketRead",
  ## the IAM user id,
  aws_iam_id: "403016165142",
  content_schema: Media.Test.Content,
  content_table: "content"

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :media, MediaWeb.Endpoint,
  http: [port: 4002],
  server: false

# Print only warnings and errors during test
config :logger, level: :warn
