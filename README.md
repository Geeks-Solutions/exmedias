# Guide

**Media** is a dependancy to manage, as the name implies, your media. By ``media`` we mean, your files such as documents, images, videos or podcasts.

  Media stores the actual files on [S3 Amazon service](https://aws.amazon.com/s3/).

## Prerequesits

**Media** relies on a [thumbnex](https://github.com/talklittle/thumbnex), therefore your environment must include these two packages:
- [ImageMagick](https://imagemagick.org/)
- [FFmpeg](https://ffmpeg.org/)

## Installation

  In your mix.exs add this to your list of dependancies:

  ```elixir
  {:media, "~> 0.1.0"}
  ```

## Configuration
#### Common Configuration

In your `router.ex`, add this line:

```elixir
use Media.Routes, scope: "/media"
```

#### PostgreSQL Based Project

If your project is connected to a ``PostgreSQL`` project then you should follow the below steps, if it is connect to ``MongoDB`` then jump to the next section.

Now in your ``config.exs`` add the following:

```elixir
config :media,
  otp_app: :your_app,
  active_database: "mongoDB",
  repo: :mongo,
  content_schema: Blogs.Schema.Article,
  content_table: "blogs",
  router: YouAppWeb.Router,
  aws_bucket_name: "your_bucket",
  aws_role_name: "you_role_to_assume_arn",
  aws_iam_id: "403016165142", ## the IAM user id
```
``active_database``: the database your project is using accepted values are: "mongoDB" or "postgreSQL"
``repo``: The mongodb application name or the repo module in case it's a postgreSQL based project i.e ``YourApp.Repo``.
``content_schema``: The content that we want to relate the medias to.
``content_table``: Your content table name.
`aws_role_name`: In AWS, you can create roles (`IAM` roles) that has certain permission. This role will be assumed in order to authenticate the access to private files
`aws_iam_id`: The IAM user ID.

**EXAMPLE**

Let's consider having an article table. As you know, articles might contain images, videos or podcasts. This is our ``content`` schema.

The content schema must reference our media table. This is how the schema module will look like:

```elixir
  schema "articles" do
  field(:title, :string)
  field(:body, :string)

  many_to_many(
    :medias,
    Media.PostgreSQL.Schema,
    join_through: "medias_contents",
    on_replace: :delete,
    join_keys: [content_id: :id, media_id: :id]
  )

  timestamps()
end
```
This will imply a simple change in your changeset too:
```elixir
  def update_changeset(article, attrs) do

  changeset =
    article
    |> cast(attrs, [
      :title,
      :body
    ])
    |> put_assoc(:medias, Map.get(attrs, :medias) || Map.get(attrs, "medias")) ## add this line add the end
end
```

Before running your project perform the following mix command:

- ``mix media.setup && mix ecto.migrate``

This command will move setup your database with the latest media migrations.

Now you are all set to start using Media. 🎉

#### MongoDB Based Project
```elixir
config :media,
  otp_app: :sections,
  active_database: "mongoDB",
  repo: :mongo,
  router: SectionsWeb.Router,
  aws_bucket_name: "eweevtestbucketprivate",
  aws_role_name: "privateBucketRead",
  aws_region: "us-east-1",
  aws_iam_id: "403016165142"
```
``active_database``: the database your project is using accepted values are: "mongoDB" or "postgreSQL"
``repo``: The mongodb application name or the repo module in case it's a postgreSQL based project i.e ``YourApp.Repo``.
``content_schema``: The content that we want to relate the medias to.
``content_table``: Your content table name.
`aws_role_name`: In AWS, you can create roles (`IAM` roles) that has certain permission. This role will be assumed in order to authenticate the access to private files
`aws_iam_id`: The IAM user ID.
  In case your project relies on a ``MongoDB``, in your  ``application.ex`` file add this tuple to the children list inside the ``start`` function:

In your ``application.ex``, add the following to `children` processes that will be supervised in your `start` function:

```elixir
children = [
  ...,
  {
  Task,
    fn ->
      Media.Helpers.create_collections()
    end
  },
  ...
]
```

By adding this, your collection will be setup properly adding the proper collections to your database.

Before running your project perform the following mix command:

- mix media.setup

Now you are all set to start using Media. 🎉