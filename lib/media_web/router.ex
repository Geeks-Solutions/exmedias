defmodule Media.Routes do
  @moduledoc """
  Media.Routes must be used in your phoenix routes as follows:

  ```elixir
  use Media.Routes, scope: "/", pipe_through: [:browser, :authenticate]
  ```

  `:scope` defaults to `"/media"`

  `:pipe_through` defaults to media's `[:media_browser]`, you can customize the pipeline as you want.

  The supported routes are:
  ```elixir
  post("/media", MediaController, :insert_media, as: :media)
  put("/media", MediaController, :update_media, as: :media)
  get("/media/:id", MediaController, :get_media, as: :media)
  post("/medias", MediaController, :list_medias, as: :media)
  delete("/media/:id", MediaController, :delete_media, as: :media)
  get("/medias/namespaced/:namespace", MediaController, :count_namespace, as: :media)

  post("/platform", PlatformController, :insert_platform, as: :media)
  post("/platforms", PlatformController, :list_platforms, as: :media)
  get("/platform/:id", PlatformController, :get_platform, as: :media)
  put("/platform/:id", PlatformController, :update_platform, as: :media)
  delete("/platform/:id", PlatformController, :delete_platform, as: :media)
  ```
  """

  # use Phoenix.Router

  defmacro __using__(options \\ []) do
    scoped = Keyword.get(options, :scope, "/media")
    custom_pipes = Keyword.get(options, :pipe_through, [])
    browser_pipes = [:media_browser] ++ custom_pipes
    api_pipes = [:media_api] ++ custom_pipes

    quote do
      pipeline :media_browser do
        plug(:accepts, ["html", "json"])
        plug(:fetch_session)
        plug(:fetch_flash)
        plug(:protect_from_forgery)
        plug(:put_secure_browser_headers)
      end

      pipeline :media_api do
        plug(:accepts, ["json"])
      end

      scope unquote(scoped), MediaWeb do
        pipe_through(unquote(browser_pipes))

        get("/", PageController, :index, as: :media)
        # get("/dashboard", HomeController, :dashboard, as: :media_dashboard)
      end

      scope unquote(scoped), MediaWeb do
        pipe_through(unquote(api_pipes))

        post("/media", MediaController, :insert_media, as: :media)
        put("/media", MediaController, :update_media, as: :media)
        get("/content/medias/:content_id", MediaController, :content_medias, as: :media)
        get("/media/:id", MediaController, :get_media, as: :media)
        post("/medias", MediaController, :list_medias, as: :media)
        delete("/media/:id", MediaController, :delete_media, as: :media)
        get("/medias/namespaced/:namespace", MediaController, :count_namespace, as: :media)

        post("/platform", PlatformController, :insert_platform, as: :media)
        post("/platforms", PlatformController, :list_platforms, as: :media)
        get("/platform/:id", PlatformController, :get_platform, as: :media)
        put("/platform/:id", PlatformController, :update_platform, as: :media)
        delete("/platform/:id", PlatformController, :delete_platform, as: :media)

        # get("/dashboard", HomeController, :dashboard, as: :media_dashboard)
      end
    end
  end
end
