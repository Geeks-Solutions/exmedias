defmodule MediaWeb.MediaView do
  @moduledoc false
  use MediaWeb, :view
  alias MediaWeb.MediaView

  def render(
        "media.json",
        %{
          media:
            %{
              title: title,
              author: author,
              tags: tags,
              type: type,
              locked_status: locked_status,
              private_status: private_status,
              seo_tag: seo_tag,
              id: id
            } = media
        } = content
      ) do
    %{
      title: title,
      author: author,
      tags: tags,
      type: type,
      locked_status: locked_status,
      private_status: private_status,
      seo_tag: seo_tag,
      id: id |> format_id(),
      number_of_contents: Map.get(media, :number_of_contents, 0),
      files: media.files |> Enum.map(&(&1 |> format_file())),
      namespace: media.namespace,
      meta: Map.get(content, :meta, %{})
    }
  end

  def render("media.json", %{media: media, meta: meta}) do
    Map.merge(media, %{meta: meta})
  end

  def render("media.json", %{media: media}) do
    media
  end

  # defp format_id(nil), do: nil

  def render("message.json", %{message: message}) do
    %{message: message}
  end

  def render("error.json", %{error: error}) do
    %{error: error}
  end

  def render("medias.json", %{medias: medias, total: total}) do
    %{result: render_many(medias, MediaView, "media.json"), total: total}
  end

  def render("medias.json", %{medias: medias}) do
    render_many(medias, MediaView, "media.json")
  end

  def render("count.json", %{total: total}) do
    %{total: total}
  end

  defp format_file(%{platform_id: %BSON.ObjectId{} = id, platform: platform} = file),
    do:
      file
      |> Map.put(:platform_id, id |> format_id())
      |> Map.put(
        :platform,
        platform
        |> Map.put(:id, platform |> Map.get(:_id) |> format_id)
        |> Map.delete(:_id)
      )

  defp format_file(%{platform_id: %BSON.ObjectId{} = id} = file),
    do:
      file
      |> Map.put(:platform_id, id |> format_id())

  defp format_file(file), do: file

  defp format_id(%BSON.ObjectId{} = id) do
    id |> BSON.ObjectId.encode!()
  end

  defp format_id(id) do
    id
  end
end
