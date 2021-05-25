defmodule Media.Schema.File do
  @moduledoc """
    This is the media schema model.
    It represents the media properties and their types.
    ```elixir
    schema "media" do
      field(:tags, {:array, :string})
      field(:title, :string)
      field(:author, :string)
      ## [%{"size"=> 1_000, url=> "http://image.com/image/1", "filename"=> "image/1"}]
      field(:files, {:array, :map})
      field(:type, :string)
      field(:locked_status, :string, default: "locked")
      field(:private_status, :string, dedfault: "private")

      many_to_many Application.get_env(:media, :content_table) |> String.to_atom(),
                 Application.get_env(:media, :content_schema),
                 join_through: "medias_contents"

      timestamps()
  end
  ```elixir
  """
  @fields ~w(url size type filename duration platform_id)a
  use Ecto.Schema
  import Ecto.Changeset
  alias Media.Helpers
  alias Media.Platforms.Platform
  # @derive {Jason.Encoder, only: @fields}
  @primary_key false
  embedded_schema do
    field(:url, :string)
    field(:filename, :string)
    field(:type, :string)
    field(:size, :integer)
    field(:duration, :integer)
    belongs_to :platform, Platform, on_replace: :delete
  end

  def changeset(file, attrs) do
    file
    |> cast(attrs, @fields)
    |> validate_required([:type, :filename, :size, :url, :platform_id])
    ## validate file extensions
    |> validate_platform_id()
  end

  def validate_platform_id(changeset) do
    platform_id = changeset |> get_field(:platform_id)

    with true <- valid_id?(platform_id), false <- is_nil(get_platform(platform_id)) do
      changeset
    else
      false ->
        changeset |> add_error(:platform, "Id provided is invalid")

      true ->
        changeset |> add_error(:platform, "Platform does not exist")
    end
  end

  defp valid_id?(id) when is_integer(id) do
    true
  end

  defp valid_id?(id) when is_binary(id) do
    Integer.parse(id)
    |> case do
      :error -> false
      {_id, _} -> true
    end
  end

  defp get_platform(nil), do: nil

  defp get_platform(id) do
    Helpers.repo().get(Platform, id)
  end
end
