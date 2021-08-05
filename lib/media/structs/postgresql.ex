defmodule Media.PostgreSQL do
  @moduledoc false
  alias Media.FiltersPostgreSQL
  alias Media.Helpers
  import Ecto.Query
  import MediaWeb.Gettext

  defstruct args: []

  defimpl DB, for: Media.PostgreSQL do
    @moduledoc """
    The PostgreSQL context.
    """

    @medias_contents "medias_contents"
    alias Media.{Helpers, Platforms}
    alias Media.Platforms.Platform
    alias Media.PostgreSQL.Schema, as: MediaSchema
    import Ecto.Query, warn: true

    def content_medias(%{args: id}) when is_integer(id) do
      {:ok, query_content_medias(id)}
    end

    def content_medias(%{args: id}) when is_binary(id) do
      case Integer.parse(id) do
        :error ->
          {:error, gettext("invalid ID")}

        {id, _} ->
          {:ok, query_content_medias(id)}
      end
    end

    def query_content_medias(id) do
      from(c in "medias_contents")
      |> join(:inner, [c], m in MediaSchema, on: m.id == c.media_id and c.content_id == ^id)
      |> select([c, m], m)
      |> Helpers.repo().all()
    end

    def count_namespace(%{args: namespace}) do
      res =
        from(m in MediaSchema,
          where: m.namespace == ^namespace,
          select: %{total: fragment("count(?)", m.id)}
        )
        |> Helpers.repo().one()

      {:ok, res}
    end

    def insert_media(%{args: attrs}) do
      %MediaSchema{}
      |> MediaSchema.changeset(attrs)
      |> Helpers.repo().insert()
    end

    def update_media(%{args: %{id: id} = params}) do
      case get_media_by_id(id) do
        {:ok, media} ->
          media
          |> MediaSchema.changeset(params)
          |> Helpers.repo().update()

        {:error, :not_found, _} = res ->
          res
      end
    end

    @doc """
    Returns the list of medias.

    ## Examples

        iex> list_medias()
        [%{}, ...]

    """
    def list_medias(%{args: args}) do
      case args |> Helpers.build_params() do
        {:error, error} ->
          error

        {:ok, %{filter: filters, sort: sort, operation: operation}} ->
          {offset, limit} =
            Helpers.build_pagination(
              Helpers.extract_param(args, :page),
              Helpers.extract_param(args, :per_page)
            )

          # related_schema = Helpers.env(:content_schema) || Helpers.env(:content_table)

          result =
            full_media_query()
            |> FiltersPostgreSQL.init(
              filters,
              operation
            )
            |> group_by([m], m.id)
            |> add_offset(offset)
            |> add_limit(limit)
            |> add_sort(sort)
            |> Helpers.repo().all()

          total = result |> Enum.at(0, %{}) |> Map.get(:total)

          result =
            result
            |> Enum.map(fn %{files: _files, media: _media} = args -> format_media(args) end)

          %{result: result, total: total}
      end
    end

    def get_media_by_type(type) do
      Helpers.repo().all(
        MediaSchema,
        from(p in MediaSchema,
          where: p.type == ^type,
          select: p
        )
      )
    end

    def delete_media(%{args: media_id}) do
      with {true, media_id} <-
             Helpers.valid_postgres_id?(media_id),
           {media, false} <- media_used?(media_id) do
        Helpers.delete_s3_files(media.files)
        delete_media_by_id(media_id)
      else
        {:error, :not_found, _} = res ->
          res

        {_media, true} ->
          {:error, "The media with ID #{media_id} is used by content, It cannot be deleted"}

        {false, -1} ->
          {:error, Helpers.id_error_message(media_id)}
      end
    end

    defp delete_media_by_id(media_id) do
      from(p in MediaSchema,
        where: p.id == ^media_id
      )
      |> Helpers.repo().delete_all()
      |> case do
        {1, nil} -> {:ok, "Media with id #{media_id} deleted successfully"}
        {0, nil} -> {:error, :not_found, "Media does not exist"}
      end
    end

    def get_media(%{args: media_id}) do
      with {true, media_id} <- Helpers.valid_postgres_id?(media_id),
           nil <- get_full_media(media_id) do
        {:error, :not_found, "Media does not exist"}
      else
        {false, -1} -> {:error, Helpers.id_error_message(media_id)}
        media -> {:ok, media |> Helpers.check_files_privacy()}
      end
    end

    def get_full_platform(id) do
      full_platform_query()
      |> where([m], m.id == ^id)
      |> Helpers.repo().one()
      |> case do
        nil ->
          nil

        %{number_of_medias: _files, platform: _media} = args ->
          format_platforms(args)
      end
    end

    def get_full_media(id) do
      full_media_query()
      |> where([m], m.id == ^id)
      |> Helpers.repo().one()
      |> case do
        nil ->
          nil

        %{files: _files, media: _media} = args ->
          format_media(args)
      end
    end

    defp format_media(%{media: media, files: files} = args) do
      files =
        files
        |> Enum.map(fn %{"file" => file, "platform" => platform} ->
          Map.put(file, "platform", platform)
        end)

      media
      |> Map.put(:files, files |> Helpers.atomize_keys())
      |> Map.put(:number_of_contents, Map.get(args, :number_of_contents))
      |> Map.delete(:total)
    end

    defp get_media_by_id(id) do
      Helpers.repo().get(MediaSchema, id)
      |> case do
        nil -> {:error, :not_found, "Media"}
        media -> {:ok, media}
      end
    end

    defp get_platform_by_id(id) do
      Helpers.repo().get(Platform, id)
      |> case do
        nil -> {:error, :not_found, gettext("Platform does not exist")}
        media -> {:ok, media}
      end
    end

    def full_media_query do
      from(m in MediaSchema)
      |> join(
        :inner_lateral,
        [m],
        f in fragment("JSON_ARRAY_ELEMENTS(ARRAY_TO_JSON(?))", m.files),
        on: true
      )
      |> join(:inner, [m, f], p in Media.Platforms.Platform,
        on: fragment("? = (? ->> 'platform_id')::BIGINT", p.id, f)
      )
      |> join(:left, [m], c in "medias_contents", on: m.id == c.media_id)
      |> select([m, f, p, c], %{
        media: m,
        files: fragment("JSONB_AGG(JSONB_BUILD_OBJECT('platform', ?, 'file', ?))", p, f),
        number_of_contents: count(c.content_id),
        total: fragment("count(?) OVER()", m.id)
      })
      |> group_by([m], m.id)
    end

    def insert_platform(%{args: args}) do
      Platforms.create_platform(args)
      |> case do
        {:ok, _platform} = res -> res
        error -> error
      end
    end

    def get_platform(%{args: platform_id}) do
      with {true, platform_id} <- Helpers.valid_postgres_id?(platform_id),
           nil <- get_full_platform(platform_id) do
        {:error, :not_found, gettext("Platform does not exist")}
      else
        {false, -1} -> {:error, Helpers.id_error_message(platform_id)}
        platform -> {:ok, platform}
      end
    end

    def update_platform(%{args: %{id: _id} = params}), do: update_platform_common(%{args: params})

    def update_platform(%{args: %{"id" => _id} = params}),
      do: update_platform_common(%{args: params})

    def update_platform(%{args: _params}), do: {:error, gettext("Please provide an ID")}

    def update_platform_common(%{args: params}) do
      case get_platform_by_id(Helpers.extract_param(params, :id)) do
        {:ok, media} ->
          media
          |> Platform.changeset(params)
          |> Helpers.repo().update()

        {:error, :not_found, _} = res ->
          res
      end
    end

    def delete_platform(%{args: platform_id}) do
      with {true, platform_id} <- Helpers.valid_postgres_id?(platform_id),
           false <- !platform_unused?(platform_id) do
        delete_platform_by_id(platform_id)
      else
        true ->
          {:error, "The platform with ID #{platform_id} is used by medias, It cannot be deleted"}

        {false, -1} ->
          {:error, Helpers.id_error_message(platform_id)}
      end
    end

    def delete_platform_by_id(platform_id) do
      from(p in Platform,
        where: p.id == ^platform_id
      )
      |> Helpers.repo().delete_all()
      |> case do
        {1, nil} -> {:ok, "Platform with id #{platform_id} deleted successfully"}
        {0, nil} -> {:error, :not_found, gettext("Platform does not exist")}
      end
    end

    def list_platforms(%{args: args}) do
      case args |> Helpers.build_params() do
        {:error, error} ->
          error

        {:ok, %{filter: filters, sort: sort, operation: operation}} ->
          {offset, limit} =
            Helpers.build_pagination(
              Helpers.extract_param(args, :page),
              Helpers.extract_param(args, :per_page)
            )

          # related_schema = Helpers.env(:content_schema) || Helpers.env(:content_table)

          result =
            full_platform_query()
            |> FiltersPostgreSQL.init(
              filters,
              operation
            )
            # |> group_by([m], m.id)
            |> add_offset(offset)
            |> add_limit(limit)
            |> add_sort(sort)
            |> Helpers.repo().all()

          total = result |> Enum.at(0, %{}) |> Map.get(:total)

          result =
            result
            |> Enum.map(fn %{total: _total, platform: _media, number_of_medias: _total_medias} =
                             args ->
              format_platforms(args)
            end)

          %{result: result, total: total || 0}
      end
    end

    def full_platform_query do
      sub_query =
        from(m in MediaSchema)
        |> join(
          :inner_lateral,
          [m],
          f in fragment("JSON_ARRAY_ELEMENTS(ARRAY_TO_JSON(?))", m.files),
          on: true
        )
        |> select([m, f], %{
          platform_id: fragment("(? ->> 'platform_id')::bigint", f),
          number_of_medias: fragment("coalesce(COUNT(?), 0)", f)
        })
        |> group_by([_], fragment("platform_id"))

      from(m in Platform)
      |> join(
        :left,
        [p],
        f in subquery(sub_query),
        on: p.id == f.platform_id
      )
      |> select([p, f], %{
        platform: p,
        number_of_medias: fragment("coalesce(?, 0)", f.number_of_medias),
        total: fragment("count(?) OVER()", p)
      })
    end

    def format_platforms(%{platform: platform, number_of_medias: total_medias}) do
      platform
      |> Map.put(:number_of_medias, total_medias)
      |> Map.delete(:total)
    end

    def media_used?(id) do
      exists? = from(m in @medias_contents, where: m.media_id == ^id) |> Helpers.repo().exists?()

      case get_media_by_id(id) do
        {:ok, media} ->
          {media, exists?}

        {:error, :not_found, _} = res ->
          res
      end
    end

    def platform_unused?(id) do
      res =
        from(m in MediaSchema,
          select: m,
          where:
            fragment(
              "exists (select * from JSON_ARRAY_ELEMENTS(ARRAY_TO_JSON(?)) as a where (a ->> 'platform_id')::bigint = ?)",
              m.files,
              ^id
            )
        )
        |> Helpers.repo().all()

      ## if there was no media using this platform the query will return an empty array
      res == []
    end

    def add_limit(query, 0), do: query

    def add_limit(query, limit) do
      query
      |> limit(^limit)
    end

    def add_offset(query, 0), do: query

    def add_offset(query, offset) do
      query
      |> offset(^offset)
    end

    def add_sort(query, nil), do: query
    def add_sort(query, sort) when sort == %{}, do: query

    def add_sort(query, sort) do
      [field | _tail] = sort |> Map.keys()
      direction = sort[field]

      field =
        cond do
          is_binary(field) -> String.to_atom(field)
          is_atom(field) -> field
          true -> raise "Sorted field can only be an atom or a string"
        end

      with false <- is_nil(direction),
           direction <- direction |> String.downcase() |> String.to_atom(),
           true <- direction in [:desc, :asc] do
        query
        |> order_by([p], [{^direction, field(p, ^field)}])
      else
        _ -> query
      end
    end
  end
end
