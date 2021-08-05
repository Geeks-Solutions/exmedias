defmodule MediaWeb.MediaController do
  @moduledoc """
  The media Controller handles the media endpoints.

  Check the routes for mapping to the right controller function.

  Note:

  As Media will have to handle with file submission, thus the user will need supply form-data body in the request. In order to see an example you can check the Postman collection shared at the root of the project. Import the Postman collection to Postman. Add the environment variable `url` that point to your project in `environment` section inside Postman.
  That's it your postman collection is ready to be used to interact with Media. The body is setup only needs the values to be filled.
  """
  use MediaWeb, :controller
  alias Media.{Context, Helpers}
  action_fallback(MediaWeb.FallbackController)

  @doc """
  Gets a `media`

  #### Request Format:

  - Media ID should be supplied as path variable. (check routes section)

  #### Response Format:

  - Status 200:

  ```json
  {
    "author": "some author id",
      "files": [
        {
          "file_id": "123123123",
          "filename": "filename_on_s3_image.jpeg",
          "platform": {
            "description": "some description",
            "height": 42,
            "id": 1609,
            "inserted_at": "2021-05-25T13:07:48",
            "name": "name",
            "updated_at": "2021-05-25T13:07:48",
            "width": 42
          },
          "platform_id": 1610,
          "size": 13900,
          "type": "image/png",
          "thumbnail_filename": "thumbnail_filename",
          "thumbnail_url": "thumbnail_url",
          "url": "url"
        }
      ],
      "id": 1075,
      "inserted_at": "2021-05-25T13:07:48",
      "locked_status": "locked",
      "number_of_contents": 0,
      "private_status": "public",
      "seo_tag": "some seo tag",
      "tags": ["tag1", "tag2"],
      "title": "some media title",
      "type": "image",
      "updated_at": "2021-05-25T13:07:48"
    }
  ```
  - Status 404:
  ```json
  {"error": "Media does not exist"}
  ```

  **IMPORTANT**:

  - Getting a public media will return the url from which you can access your media *directly*.
  - Getting a private media will return the url from which you can access your media and the headers that you should supply too to authenticate your request. Make sure to request your media as soon as possible because the request is valid for a short notice.
  The format of the headers is the following ``%{"headers"=> %{"header"=> "value", "header1"=> value1}}``
  """
  def get_media(conn, %{"id" => id}) do
    case Context.get_media(id) do
      {:ok, media} -> render(conn, "media.json", media: media)
      {:error, :not_found, _} = fall_back_error -> fall_back_error
    end
  end

  @doc """
  Lists a `media`.

  You can get a list of available `medias`.

  The list can be filtered, sorted and paginated.

  #### Response Format:

  The body format expected for each type of request:

  - Listing all available medias:

  ```json
  {}
  ```

  - Listing medias paginated:

  ```json
  {"page": 1, "per_page": 10}
  ```

  - Listing medias sorted:

  ```json
  {"sort": {"id": "desc"}} ## [desc DESC ASC asc] are accepted
  ```
  - Listing all available medias sorted:

  ```json
  {"sort": {"id": "desc"}} ## [desc DESC ASC asc] are accepted
  ```

  - Listing all available medias filtered:

  ```json
  {"filters": [{"key": "number_of_contents", "value": 10, "operation": "<" }]}
  {"filters": [{"key": "id", "value": 134}]}
  {"filters": [{"key": "number_of_contents", "value": 5, "operation": ">" }, {"key": "type", "value": "image"}]}
  ```
  Available operations are: `<`, `>`, `<>`, `between`, `=`, `<=` and `>=`.

  Default operation is `=`.

  Filters can be combined together.

  #### Response Format:
  ```json
  {"result": list_of_medias, "total": total} // list_of_medias can be an empty list if no result found and the total will be 0
  ```
  """
  def list_medias(conn, args) do
    %{result: medias, total: total} = Context.list_medias(args)
    render(conn, "medias.json", medias: medias, total: total)
  end

  def content_medias(conn, %{"content_id" => id}) do
    case Context.content_medias(id) do
      {:ok, medias} ->
        render(conn, "medias.json", medias: medias)

      {:error, error} ->
        render(conn |> put_status(400), "error.json", error: error)
    end
  end

  @doc """
  Inserts a `media`

  #### Request Format:

  In the body we expected the following format:

  ```json
    {
      "title": "Media title",
      "author": "AUTHOR_ID",
      "tags": ["technology"],
      "type": "image",
      "files":[
        {
          "file": file // The file here is uploaded using multi part. (Phoenix will take care to store as ``Plug.Upload`` struct and pass it to the controller)
          "platform_id": 10
        },
        {"file": {"url": "youtube_url"}, "platform_id": 11}
      ],
      "locked_status": "locked",
      "private_status": "public",
    }

  ```
  ```json
  {
    "author": "some author id",
      "files": %{"1"=>
        {
          "file_id": "123123123",
          "filename": "filename_on_s3_image.jpeg",
          "platform": {
            "description": "some description",
            "height": 42,
            "id": 1609,
            "inserted_at": "2021-05-25T13:07:48",
            "name": "name",
            "updated_at": "2021-05-25T13:07:48",
            "width": 42
          },
          "platform_id": 1610,
          "size": 13900,
          "type": "image/png",
          "thumbnail_filename": "thumbnail_filename",
          "thumbnail_url": "thumbnail_url",
          "url": "url"
        }
      },
      "id": 1075,
      "inserted_at": "2021-05-25T13:07:48",
      "locked_status": "locked",
      "number_of_contents": 0,
      "private_status": "public",
      "seo_tag": "some seo tag",
      "tags": ["tag1", "tag2"],
      "title": "some media title",
      "type": "image",
      "updated_at": "2021-05-25T13:07:48"
    }
  }
  ```
  - Status 400:
  ```json
  {"error": "Author can't be blank"}
  ```
  """

  def insert_media(conn, %{"files" => _files} = args) do
    args = parse_form_data(args)

    case Context.insert_media(args |> Helpers.atomize_keys()) do
      {:ok, media} ->
        render(conn, "media.json", media: media)

      {:error, %Ecto.Changeset{}} = fall_back_error ->
        fall_back_error

      {:error, error} ->
        render(conn |> put_status(400), "error.json", error: error)
    end
  end

  @doc """
  Updates a `media`

  #### Request Format:

  In the body we expected the following format:

  ```json
    {
      "title": "Media title",
      "author": "AUTHOR_ID",
      "tags": ["technology"],
      "type": "image",
      "files": %{
        "file1" =>
        {
          "file": file // The file here is uploaded using multi part. (Phoenix will take care to store as ``Plug.Upload`` struct and pass it to the controller)
          "platform_id": 10
        },
        {"file": {"url": "youtube_url"}, "platform_id": 11}
      },
      "locked_status": "locked",
      "private_status": "public",
    }

  ```
  ```json
  {
    "author": "some author id",
      "files": [
        {
          "file_id": "123123123",
          "filename": "filename_on_s3_image.jpeg",
          "platform": {
            "description": "some description",
            "height": 42,
            "id": 1609,
            "inserted_at": "2021-05-25T13:07:48",
            "name": "name",
            "updated_at": "2021-05-25T13:07:48",
            "width": 42
          },
          "platform_id": 1610,
          "size": 13900,
          "type": "image/png",
          "thumbnail_filename": "thumbnail_filename",
          "thumbnail_url": "thumbnail_url",
          "url": "url"
        }
      ],
      "id": 1075,
      "inserted_at": "2021-05-25T13:07:48",
      "locked_status": "locked",
      "number_of_contents": 0,
      "private_status": "public",
      "seo_tag": "some seo tag",
      "tags": ["tag1", "tag2"],
      "title": "some media title",
      "type": "image",
      "updated_at": "2021-05-25T13:07:48"
    }
  ```
  - Status 400:
  ```json
  {"error": "Author can't be blank"}
  ```

  The files update is complete so any old files that will be missing in the payload will be deleted. Only the files that are sent will be reachable.
  """
  def update_media(conn, %{"id" => _id} = args) do
    args = parse_form_data(args)

    case Context.update_media(args |> Helpers.atomize_keys()) do
      {:ok, media} ->
        render(conn, "media.json", media: media)

      {:error, %Ecto.Changeset{}} = fall_back_error ->
        fall_back_error
    end
  end

  def update_media(conn, _args),
    do: render(conn, "error.json", error: "Please provide an Id to update a media")

  @doc """
  Deletes a `media`

  #### Request Format:

  - Media ID should be supplied as path variable. (check routes section)

  #### Response Format:
  - Status 200:

  ```json
  {"error": "Media with id 1 deleted successfully"}
  ```
  - Status 404:
  ```json
  {"error": "Media does not exist"}
  ```
  """
  def delete_media(conn, %{"id" => id}) do
    case Context.delete_media(id) do
      {:ok, message} -> render(conn, "message.json", message: message)
      {:error, :not_found, _} = fall_back_error -> fall_back_error
      {:error, error} -> render(conn |> put_status(400), "error.json", error: error)
    end
  end

  def count_namespace(conn, %{"namespace" => namespace}) do
    {:ok, %{total: total}} = Context.count_namespace(namespace)
    render(conn, "count.json", total: total)
  end

  defp parse_form_data(%{"files" => nil} = args), do: Map.put(args, "files", [])

  defp parse_form_data(%{"files" => files} = args) when is_map(args) do
    files = files |> Enum.map(fn {_key, value} -> value end)
    Map.put(args, "files", files)
  end

  defp parse_form_data(args), do: args
end
