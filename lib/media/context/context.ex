defmodule Media.Context do
  @moduledoc """
    The context module defines the functions that should be invoked in the parent app.
    Consider this as the API of Media APP.
  """
  alias Media.Helpers

  @doc """
  Inserts a `media`

  Usage:

  You can insert `media` by calling the following function

  ```elixir
  Media.Context.insert_media(
    %{
      title: "Media title",
      author: "AUTHOR_ID",
      tags: ["technology"],
      type: "video",
      files: [
        %{file: %{url: "https://www.youtube.com/watch?v=3HkggxR_kvE"}, platform_id: "609bd3b50a99863f954c1133"}
      ],
      locked_status: "locked",
      private_status: "public",
      namespace: "projec1"
    }
  )
  ```
  Return possibilities:
  ```elixir
  {:ok, media}
  {:error, changeset}
  ```
  """

  def insert_media(args, opts \\ %{}) do
    case DB.insert_media(Helpers.db_struct(args)) do
      {:ok, media} ->
        {:ok, media |> Helpers.render(%{return_type: Map.get(opts, :return_type, :struct)})}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Gets a `media`

  Usage:

  You can get a `media` by its id with

  ```elixir
  Media.Context.get_media(your_media_id)
  ```

  Returns possibilities:

  ```elixir
   {:ok, media}
   {:error, changeset}
   {:error, :not_found, message}
   {:error, message}
  ```

  **IMPORTANT**:

  - Getting a public media will return the url from which you can access your media *directly*.
  - Getting a private media will return the url from which you can access your media and the headers that you should supply too to authenticate your request. Make sure to request your media as soon as possible because the request is valid for a short notice.
  The format of the headers is the following %{headers: %{header: value, header1: value1}}
  """
  def get_media(args, opts \\ %{}) do
    case DB.get_media(Helpers.db_struct(args)) do
      {:ok, media} ->
        {:ok, media |> Helpers.render(%{return_type: Map.get(opts, :return_type, :struct)})}

      {:error, _} = err ->
        err

      {:error, _, _} = err ->
        err
    end
  end

  @doc """
  Lists a `media`.

  You can get a list of available `medias`.

  The list can be filtered, sorted and paginated.

  Usage examples:

  Listing all available medias:

  ```elixir
  Media.Context.get_medias()
  ```

  Listing medias paginated:

  ```elixir
  Media.Context.get_medias(%{page: 1, per_page: 10})
  ```

  Listing medias sorted:

  ```elixir
  Media.Context.get_medias(%{sort: %{id: "desc"}}) ## [desc DESC ASC asc] are accepted
  ```
  Listing all available medias sorted:

  ```elixir
  Media.Context.get_medias(%{sort: %{id: "desc"}}) ## [desc DESC ASC asc] are accepted
  ```

  Listing all available medias filtered:

  Filtering supports both conditions `OR` and `AND`, it all depends on how you provide the structure of your filters.

  If we want to provide for example the following filter:
  ``(title=my_portrait and type=image) or (private_status=public)``

  we supply the following payload:
  ```elixir
  %{
    filters: [
        [
            %{
                key: "title",
                value: "my_portrait"
            },
            %{
                key: "type",
                value: "image"
            }
        ],
        [
            %{
                key: "private_status",
                value: "public"
            }
        ]
    ]
  }
  ```

  ```elixir
  Media.Context.get_medias(%{filters: [[%{key: "number_of_contents", value: 10, operation: "<" }]]})
  Media.Context.get_medias(%{filters: [[%{key: "id", value: 134}]]})
  Media.Context.get_medias(%{filters: [[%{key: "number_of_contents", value: 5, operation: ">" }, %{key: "type", value: "image"}]]})
  ```
  Available operations are: `<`, `>`, `<>`, `between`, `=`, `<=` and `>=`.

  Default operation is `=`.

  Filters can be combined together.

  ```elixir
  %{result: list_of_medias, total: total} ## list_of_medias can be an empty list if no result found and the total will be 0
  ```
  """

  def list_medias(args \\ %{}, opts \\ %{}) do
    %{total: total, result: medias} = DB.list_medias(Helpers.db_struct(args))
    ## renders srtucts or maps
    %{
      total: total,
      result: medias |> Helpers.render(%{return_type: Map.get(opts, :return_type, :struct)})
    }
  end

  @doc """

  """
  def content_medias(args \\ %{}, opts \\ %{}) do
    case DB.content_medias(Helpers.db_struct(args)) do
      {:error, _} = err ->
        err

      {:error, _, _} = err ->
        err

      {:ok, result} ->
        {:ok, result |> Helpers.render(%{return_type: Map.get(opts, :return_type, :struct)})}
    end
  end

  @doc """
  Deletes a media

  You can delete a `media` by its id

  Usage:

  ```elixir
  Media.Context.delete_media(media_id)
  ```
  Notes:
  - You cannot delete a media that is used by a content.

  Returns possibilities:
  ```elixir
  {:ok, message}
  {:error, message}
  {:error, :not_found, message}
  ```
  """
  def delete_media(args) do
    DB.delete_media(Helpers.db_struct(args))
  end

  def dereference_content(args) do
    DB.dereference_content(Helpers.db_struct(args))
  end

  @doc """
  Updates a `media`.

  The files update is a complete update and not a partial one. If you would like to keep the old files and add to them you just need to supply the file id you want to keep.


  Usage:

  You can update `media` by calling the following function if you want to upload new files.

  ```elixir
  Media.Context.update_media(
    %{
      title: "Media title",
      author: "AUTHOR_ID",
      tags: ["technology"],
      type: "image",
      files: [%Plug.Upload{path: "path/to/file", filename: "image/image.png", content_type: "image/png"}],
      locked_status: "locked",
      private_status: "public",
    }
  )
  ```
    You can update `media` by calling the following function if you want to add new files to existing ones.

  ```elixir
  Media.Context.update_media(
    %{
      title: "Media title",
      author: "AUTHOR_ID",
      tags: ["technology"],
      type: "image",
      files: [%{file_id: "hacmnzxiuh123ad"}, %Plug.Upload{path: "path/to/file", filename: "image/image.png", content_type: "image/png"}],
      locked_status: "locked",
      private_status: "public",
    }
  )
  ```
  returns possibilities
  ```elixir
  {:ok, media}
  {:error, changeset}
  ```

  """
  def update_media(args, opts \\ %{}) do
    case DB.update_media(Helpers.db_struct(args)) do
      {:ok, media} ->
        {:ok, media |> Helpers.render(%{return_type: Map.get(opts, :return_type, :struct)})}

      {:error, _} = err ->
        err

      {:error, _, _} = err ->
        err
    end
  end

  @doc """
  Inserts a `platform`

  Usage:

  ```elixir
  Media.Context.insert_platform(
    %{
      name: "Media name",
      wdith: 100,
      height: ["technology"],
      description: "Description about your platform"
    }
  )
  ```
  Return possibilities:
  ```elixir
  {:ok, media}
  {:error, changeset}
  ```
  """

  def insert_platform(args, opts \\ %{}) do
    case DB.insert_platform(Helpers.db_struct(args)) do
      {:ok, platform} ->
        {:ok, platform |> Helpers.render(%{return_type: Map.get(opts, :return_type, :struct)})}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Gets a `platform`

  Usage:

  You can get a `platform` by its id with

  ```elixir
  Media.Context.get_platform(YOUR_MEDIA_ID)
  ```
  Returns possibilities:
  ```elixir
   {:ok, platform}
   {:error, changeset}
   {:error, :not_found, message}
   {:error, message}
  ```
  """
  def get_platform(args, opts \\ %{}) do
    case DB.get_platform(Helpers.db_struct(args)) do
      {:ok, platform} ->
        {:ok, platform |> Helpers.render(%{return_type: Map.get(opts, :return_type, :struct)})}

      {:error, _} = err ->
        err

      {:error, _, _} = err ->
        err
    end
  end

  @doc """
  Lists a `platform`.

  You can get a list of available `platforms`.

  The list can be filtered, sorted and paginated.

  Usage examples:

  Listing all available platforms:

  ```elixir
  platform.Context.list_platforms()
  ```

  Listing platforms paginated:

  ```elixir
  Media.Context.list_platforms(%{page: 1, per_page: 10})
  ```

  Listing platforms sorted:

  ```elixir
  Media.Context.list_platforms(%{sort: %{id: "desc"}}) ## [desc DESC ASC asc] are accepted
  ```
  Listing all available platforms sorted:

  ```elixir
  Media.Context.list_platforms(%{sort: %{id: "desc"}}) ## [desc DESC ASC asc] are accepted
  ```
  The same filtering rules used for listing medias.

  Listing all available platforms filtered:
  ```elixir
  Media.Context.list_platforms(%{filters: [[%{key: "number_of_medias", value: 10, operation: "<" }]]})
  Media.Context.list_platforms(%{filters: [[%{key: "id", value: 134}], [%{key: "name", value: "mobile"}]]})
  Media.Context.list_platforms(%{filters: [[%{key: "number_of_medias", value: 5, operation: ">" }, %{key: "name", value: "name of platform"}]]})
  ```
  Available operations are: `<`, `>`, `<>`, `between`, `=`, `<=` and `>=`.

  Default operation is `=`.

  Filters can be combined together.

  Returns possibilities
  ```elixir
  %{result: list_of_platform, total: total} ## list_of_platforms can be an empty list if no result found and the total will be 0
  ```
  """
  def list_platforms(args \\ %{}, opts \\ %{}) do
    %{result: platforms, total: total} = DB.list_platforms(Helpers.db_struct(args))

    %{
      result: platforms |> Helpers.render(%{return_type: Map.get(opts, :return_type, :struct)}),
      total: total
    }
  end

  @doc """
  Updates a `platform`

  Usage:

  ```elixir
  Media.Context.update_platform(
    %{
      name: "Apple TV",
      description: "Describe your platform",
      width: ["technology"],
      height: 200,
      id: 1
    }
  )
  ```
  Returns possibilities
  - ``{:ok, platform}``
  - ``{:error, changeset}``
  """
  def update_platform(args, opts \\ %{return_type: :struct}) do
    case DB.update_platform(Helpers.db_struct(args)) do
      {:ok, platform} ->
        {:ok, platform |> Helpers.render(%{return_type: Map.get(opts, :return_type, :struct)})}

      {:error, _} = err ->
        err

      {:error, _, _} = err ->
        err
    end
  end

  @doc """
  Deletes a platform

  You can delete a `platform` by its id

  Usage:

  ```elixir
  Media.Context.delete_platform(platofrm_id)
  ```

  Notes:
  - You cannot delete a platform that is used by a media.

  Returns possibilities:
  ```elixir
    {:ok, message}
    {:error, message}
    {:error, :not_found, message}
  ```
  """
  def delete_platform(args) do
    DB.delete_platform(Helpers.db_struct(args))
  end

  @doc """
  Namespaces are used to Group media to a certain namespace.

  This Function call was created to ensure a performant count over the medias that are related to the same name space.

  Use this call when you only need the count instead of relying on the total returned with the ``list_medias`` call.
  """
  def count_namespace(args) do
    DB.count_namespace(Helpers.db_struct(args))
  end
end
