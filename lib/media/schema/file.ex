defmodule Media.Schema.File do
  @moduledoc """
    This is the media schema model.
    It represents the media properties and their types.
    ```elixir
   @primary_key false
  embedded_schema do
    field(:url, :string)
    field(:filename, :string)
    field(:type, :string)
    field(:size, :integer)
    field(:duration, :integer)
    ## can be the s3_id, youtube_video_id etc..
    field(:file_id, :string)
    field(:thumbnail_url, :string)
    belongs_to :platform, Platform, on_replace: :delete
  end
  ```elixir
  """
  @fields ~w(url size type filename duration platform_id file_id thumbnail_url)a
  @videos_ext ["mp4"]
  @derive {Jason.Encoder, only: @fields}
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
    ## can be the s3_id, youtube_video_id etc..
    field(:file_id, :string)
    field(:thumbnail_url, :string)
    field(:metadata, :map)
    belongs_to :platform, Platform, on_replace: :update
  end

  def changeset(file, attrs) do
    file
    |> cast(attrs, @fields)
    |> validate_required([:type, :url, :platform_id, :thumbnail_url, :file_id])
    |> validate_video()

    ## validate file extensions
  end

  def validate_video(changeset) do
    validate_video(changeset, changeset |> get_field(:type))
  end

  defp validate_video(%Ecto.Changeset{valid?: false} = changeset, _type), do: changeset

  defp validate_video(%Ecto.Changeset{valid?: true} = changeset, video_ext)
       when video_ext in @videos_ext do
    duration_field = changeset |> get_field(:duration)

    cond do
      is_nil(duration_field) ->
        changeset |> add_error(:duration, "Videos must be provided with their duration")

      is_integer(duration_field) ->
        changeset

      is_binary(duration_field) and Helpers.binary_is_integer?(duration_field |> Integer.parse()) ->
        changeset

      true ->
        changeset
        |> add_error(:duration, "The duration of the video must be an integer (in seconds)")
    end
  end

  defp validate_video(%Ecto.Changeset{valid?: true} = changeset, _type), do: changeset
end
