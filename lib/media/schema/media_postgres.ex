defmodule Media.PostgreSQL.Schema do
  @moduledoc """
    This is the media schema model for PostgreSQL Databases.
    It represents the media properties and their types.
    ```elixir
    schema "media" do
      field(:tags, {:array, :string})
      field(:title, :string)
      field(:author, :string)
      embeds_many(:files, File, on_replace: :delete)
      field(:type, :string)
      field(:locked_status, :string, default: "locked")
      field(:private_status, :string, dedfault: "private")
      field(:seo_tag, :string)

      timestamps()
    end
  ```elixir


  """
  # @common_metadata ~w(platform_id url size type filename file_id)a
  # @metadata_per_type %{"video" => ~w(duration)a, "podcast" => ~w(duration)a}
  use Ecto.Schema
  import Ecto.Changeset
  alias Media.Helpers
  alias Media.Schema.File

  @fields ~w(title author tags type locked_status private_status seo_tag namespace)a
  @derive {Jason.Encoder,
           only: @fields ++ [:id, :number_of_contents, :files, :updated_at, :inserted_at]}
  schema "media" do
    field(:tags, {:array, :string})
    field(:title, :string)
    field(:author, :string)
    embeds_many(:files, File, on_replace: :delete)
    field(:type, :string)
    field(:locked_status, :string, default: "locked")
    field(:private_status, :string, dedfault: "private")
    field(:seo_tag, :string)
    field(:namespace, :string)

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
      |> cast(attrs, @fields)
      |> validate_inclusion(:locked_status, ["locked", "unlocked"])
      |> validate_required([:author, :type])
      |> validate_inclusion(:private_status, ["public", "private"])
      |> validate_inclusion(:type, ["image", "video", "document", "podcast"])
      |> Helpers.update_files(attrs)

    changeset = Map.put(changeset, :params, attrs)

    changeset
    |> Helpers.validate_platforms(attrs)
    |> put_embed(
      :files,
      attrs |> Helpers.extract_param(:files)
    )

    # |> put_assoc(
    #   Helpers.env(:content_table) |> String.to_atom(),
    #   parse_content(
    #     attrs |> Map.get(Helpers.env(:content_table) |> String.to_atom()) ||
    #       attrs |> Map.get(Helpers.env(:content_table))
    #   )
    # )
  end

  # defp parse_content(nil), do: []

  # defp parse_content(params) when params == [], do: nil

  # defp parse_content(params) do
  #   params
  #   |> Enum.map(&get_content/1)
  #   |> Enum.reject(&is_nil/1)
  # end

  # defp get_content(id) do
  #   Helpers.repo().get(Helpers.env(:content_schema), id)
  # end
end
