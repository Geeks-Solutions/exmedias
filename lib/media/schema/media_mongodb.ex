defmodule Media.MongoDB.Schema do
  import MediaWeb.Gettext

  @moduledoc """
    This is the media schema model.
    It represents the media properties and their types.
    ```elixir
    schema "media" do
    field(:tags, {:array, :string})
    field(:title, :string)
    field(:author, :string)
    field(:contents_used, {:array, :string}, default: [])
    ## [%{"size"=> 1_000, url=> "http://image.com/image/1", "filename"=> "image/1"}]
    field(:files, {:array, :map})
    field(:type, :string)
    field(:locked_status, :string, default: "locked")
    field(:private_status, :string, default: "private")
    field(:seo_tag, :string)
    ## can be used for grouping media together.
    field(:namespace, :string)
    ## virtual as this will not be stored in the database but will be returned when querying
    ## so that we have a proper mapping with the schema
    field(:number_of_contents, :integer, virtual: true, default: 0)

    timestamps()
  ```elixir
  """
  @common_file_metadata ~w(url type platform_id file_id thumbnail_url)a
  @file_metadata_per_type %{
    "video" => ~w(duration)a,
    "podcast" => ~w(duration filename)a,
    "image" => ~w(size filename metadata)a,
    "document" => ~w(size filename)a
  }
  use Ecto.Schema
  import Ecto.Changeset
  alias Media.Helpers

  @fields ~w(title author seo_tag contents_used tags type locked_status private_status files namespace)a
  @derive {Jason.Encoder, only: @fields}
  schema "media" do
    field(:tags, {:array, :string})
    field(:title, :string)
    field(:author, :string)
    field(:contents_used, {:array, :string}, default: [])
    ## [%{"size"=> 1_000, url=> "http://image.com/image/1", "filename"=> "image/1"}]
    field(:files, {:array, :map})
    field(:type, :string)
    field(:locked_status, :string, default: "locked")
    field(:private_status, :string, default: "private")
    field(:seo_tag, :string)
    field(:namespace, :string)
    ## virtual as this will not be stored in the database but will be returned when querying
    ## so that we have a proper mapping with the schema
    field(:number_of_contents, :integer, virtual: true, default: 0)

    timestamps()
  end

  @doc """
  In the changeset function, we validate the user's inputs.

  - We make sure ``locked_status`` is included in the values ``locked`` or ``unlocked``, also the ``private_status`` is eirther ``public`` or ``private``.

  - Both fields ``type`` and ``author`` are required.

  - Media ``type`` can be either ``image``, ``video``, ``document``, ``podcast``

  - Finally we validate the files input based on the type:

    - All the medias should have the following fields: ``platform``, ``size`` (in mb).

    - ``Podcasts`` and ``videos`` also have a ``duration`` field.

  Example of a media struct:

  ```elixir
  %{
  title: "Welcome Image",
  seo_tag: "seo optimization2",
  tags: ["nature", "green"],
  author: "John Doe",
  contents_used: ["2"],
  type: "image",
  files: [
      %{
        url: "https://path_to_image.com",
        size: 4_000,
        type: "png",
        filename: "image.png",
        platform_id: 1,
        thumbnail_url:  "https://path_to_thumbnail_image.com"
      }
    ]
  }
  ```
  """

  def changeset(media, attrs) do
    {changeset, attrs} =
      media
      |> cast(attrs, @fields -- [:files])
      |> validate_inclusion(:locked_status, ["locked", "unlocked"])
      |> validate_required([:author, :type])
      |> validate_inclusion(:private_status, ["public", "private"])
      |> validate_inclusion(:type, ["image", "video", "document", "podcast"])
      |> validate_contents_used(
        attrs |> Map.get(:contents_used) || attrs |> Map.get("contents_used")
      )
      |> Helpers.update_files(attrs)

    changeset
    |> Helpers.validate_platforms(attrs)
    |> cast(attrs, [:files])
    |> validate_files(attrs |> Map.get(:files) || attrs |> Map.get("files"))
  end

  defp validate_contents_used(%Ecto.Changeset{valid?: false} = changeset, _content), do: changeset
  defp validate_contents_used(%Ecto.Changeset{valid?: true} = changeset, nil), do: changeset

  defp validate_contents_used(%Ecto.Changeset{valid?: true} = changeset, content)
       when content == [],
       do: changeset

  defp validate_contents_used(%Ecto.Changeset{valid?: true} = changeset, content)
       when is_list(content) do
    if Enum.all?(content, &Helpers.valid_object_id?(&1)) do
      changeset |> put_change(:contents_used, Enum.uniq(content))
    else
      changeset |> add_error(:contents_used, "Content can only be a list of valid IDs")
    end
  end

  defp validate_files(%Ecto.Changeset{valid?: false} = changeset, _files), do: changeset

  defp validate_files(changeset, files) when is_nil(files), do: changeset

  defp validate_files(changeset, files) when files == [], do: changeset

  defp validate_files(changeset, files) do
    type = changeset |> get_field(:type)

    files
    |> validate_contents(type)
    |> case do
      {:error, error} -> changeset |> add_error(:files, error)
      files -> changeset |> put_change(:files, files)
    end
  end

  defp validate_contents(files, type) do
    {_valid, result} =
      files
      |> Enum.reduce(
        {true, []},
        fn
          file, {true, acc} ->
            {valid, content} = validate_content(file, type)
            content = if valid, do: [content] ++ acc, else: content
            {true and valid, content}

          _file, {false, result} ->
            {false, result}
        end
      )

    result
  end

  defp validate_content(file, _type) when file == %{},
    do: {:error, gettext("Do not provide empty files")}

  defp validate_content(file, type) when is_map(file) do
    {:ok, file} =
      file
      |> Morphix.atomorphify()

    required_fields = @common_file_metadata ++ Map.get(@file_metadata_per_type, type, [])

    provided_fields =
      file
      |> Map.delete(:file)
      |> Map.keys()

    with {:keys, true} <-
           {:keys,
            provided_fields
            |> Enum.all?(&(&1 in required_fields and valid_value(&1, file |> Map.get(&1)))) and
              :erlang.length(provided_fields) == :erlang.length(required_fields)},
         platform_id <- Map.get(file, :platform_id, ""),
         {:platforms, true} <-
           {:platforms,
            (platform_id |> Helpers.convert_from_object_id()) in available_platforms_ids()} do
      {true, file |> Map.put(:platform_id, platform_id |> Helpers.convert_to_object_id())}
    else
      {:keys, false} ->
        {false,
         {:error,
          "You provided invalid keys for the files. Please Make sure to provide the supported metadata on files"}}

      {:platforms, false} ->
        {false, {:error, "Invalid Platform, Make sure to provide an existing platform"}}
    end
  end

  defp valid_value(:duration, duration_value) do
    cond do
      is_nil(duration_value) ->
        false

      is_integer(duration_value) ->
        true

      is_binary(duration_value) and Helpers.binary_is_integer?(duration_value |> Integer.parse()) ->
        true

      true ->
        false
    end
  end

  defp valid_value(_, _), do: true

  defp validate_content(_files, _type),
    do: {:error, "The format of the files sent is not supported, please send a list of files"}

  # defp mapify(res) when is_struct(res), do: Map.from_struct(res)
  # defp mapify(res), do: res

  defp available_platforms_ids do
    %{result: result} = DB.list_platforms(%Media.MongoDB{args: %{}})
    result |> Enum.map(&Map.get(&1, :id))
  end
end
