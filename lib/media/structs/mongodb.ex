defmodule Media.MongoDB do
  @moduledoc false
  defstruct args: []

  defimpl DB, for: Media.MongoDB do
    @media_collection "media"
    @platform_collection "platform"
    @schema_collection %{"platform" => Media.Platforms.Platform, "media" => Media.MongoDB.Schema}
    alias BSON.ObjectId
    alias Media.{FiltersMongoDB, Helpers, MongoDB}
    alias Media.MongoDB.Schema, as: MediaSchema
    alias Media.Platforms.Platform
    import MediaWeb.Gettext

    def dereference_content(%{args: %{media_id: media_id, content_id: content_id}}) do
      with true <- Helpers.valid_object_id?(media_id),
           {:ok, %{"contents_used" => contents_used} = media} <- media_by_id(media_id),
           {:content, true} <- {:content, content_id in contents_used},
           data <-
             MediaSchema.changeset(
               struct(%MediaSchema{}, media |> Helpers.atomize_keys()),
               %{
                 contents_used: contents_used -- [content_id]
               }
             ),
           {_data, true} <- {data, data.valid?} do
        update(data, media_id, @media_collection)
      else
        {:content, false} ->
          {:error, "Content is not used by this media"}

        false ->
          {:error, "Invalid id"}

        {:error, :not_found, _collection} ->
          {:error, %{error: "#{@media_collection} does not exist"}}

        {data, false} ->
          {:error, data}
      end
    end

    def content_medias(%{args: id}) do
      if Helpers.valid_object_id?(id) do
        %{result: result} =
          list_medias(%MongoDB{args: %{filters: [[%{key: "contents_used", value: id}]]}})

        {:ok, result}
      else
        {:error, "Invalid id"}
      end
    end

    def count_namespace(%{args: namespace}) do
      {:ok, total} = Mongo.count(:mongo, @media_collection, %{namespace: namespace})
      {:ok, %{total: total}}
    end

    ## TO DO to be altered in next issues
    def list_platforms(%MongoDB{args: args}) do
      args = args |> Helpers.atomize_keys()

      pagination_pipe =
        Helpers.build_pagination(
          Helpers.extract_param(args, :page),
          Helpers.extract_param(args, :per_page)
        )
        |> case do
          {0, 0} ->
            []

          {offset, limit} ->
            [
              %{"$skip" => offset},
              %{"$limit" => limit}
            ]
        end

      ## We build the filters and valdiate them
      {sort_pipe, filters_pipe} =
        with {:ok, %{filter: filters, sort: sort, operation: operations}} <-
               args |> Helpers.build_params(),
             sort <- FiltersMongoDB.build_sort(sort),
             {sort, []} <-
               {sort,
                FiltersMongoDB.init(
                  filters,
                  operations
                )} do
          {sort, []}
        else
          {:error, error} ->
            error

          {sort, {initial_computation, computed_filters, normal_filters}} ->
            ## this can be used later for further computations
            ## so we can optimize our query (running the normal filters first for ex.)
            # initial_computations ++
            {sort,
             initial_computation ++
               format_fitlers(normal_filters) ++
               format_fitlers(computed_filters)}
        end

      ## We always need to have the number of contents_used computed
      ## disregarding the filters
      query_collection(
        @platform_collection,
        filters_pipe,
        join_pipe_platform(),
        sort_pipe,
        pagination_pipe
      )

      # Mongo.find(Media.Helpers.repo(), "platform", %{})
      # |> Media.Helpers.format_result(schema_to_module("platform"))
    end

    @doc """
    Media.Context.list_medias(%{
        args: %{
          page: 0,
          per_page: 10,
          filters: [
            %{key: "title", value: "value"},
            %{key: "number_field", value: 10, operation: "<"}
          ],
          sort: %{title: "desc"}
        }
      })

    """
    def list_medias(%MongoDB{args: args}) do
      args = args |> Helpers.atomize_keys()

      pagination_pipe =
        Helpers.build_pagination(
          Helpers.extract_param(args, :page),
          Helpers.extract_param(args, :per_page)
        )
        |> case do
          {0, 0} ->
            []

          {offset, limit} ->
            [
              %{"$skip" => offset},
              %{"$limit" => limit}
            ]
        end

      ## We build the filters and valdiate them
      {sort_pipe, filters_pipe} =
        with {:ok, %{filter: filters, sort: sort, operation: operations}} <-
               args |> Helpers.build_params(),
             sort <- FiltersMongoDB.build_sort(sort),
             {sort, []} <-
               {sort,
                FiltersMongoDB.init(
                  filters,
                  operations
                )} do
          {sort, []}
        else
          {:error, error} ->
            error

          {sort, {initial_computation, computed_filters, normal_filters}} ->
            ## this can be used later for further computations
            ## so we can optimize our query (running the normal filters first for ex.)
            # initial_computations ++
            {sort,
             initial_computation ++
               format_fitlers(normal_filters) ++
               format_fitlers(computed_filters)}
        end

      ## We always need to have the number of contents_used computed
      ## disregarding the filters
      query_collection(
        @media_collection,
        number_of_contents() ++ filters_pipe,
        join_pipe(),
        sort_pipe,
        pagination_pipe
      )
    end

    # filters to pipeline
    defp format_fitlers(filters) do
      if filters == [], do: [], else: [%{"$match" => %{"$and" => filters}}]
    end

    def insert_media(args), do: insert(args, @media_collection)

    ## When submitting the form this will be called inside the controller after the file management is done
    def update_media(%MongoDB{args: %{id: id} = args}) do
      with {:ok, %MediaSchema{} = media} <- get(%MongoDB{args: id}, @media_collection),
           data <- MediaSchema.changeset(media, args),
           {_data, true} <- {data, data.valid?} do
        update(data, id, @media_collection)
      else
        {:error, :not_found, _collection} ->
          {:error, %{error: "#{@media_collection} does not exist"}}

        {data, false} ->
          {:error, data}
      end
    end

    def delete_media(%MongoDB{args: id} = args) do
      with true <- Helpers.valid_object_id?(id), {media, false} <- media_used?(id) do
        Helpers.delete_s3_files(media.files)
        delete(args, @media_collection)
      else
        {:error, :not_found, _message} = res ->
          res

        {_media, true} ->
          {:error, "This Media cannot be deleted as it used by contents."}

        false ->
          {:error, Helpers.id_error_message(id)}
      end
    end

    def media_used?(id) do
      case get(%MongoDB{args: id}, @media_collection) do
        {:ok, media} ->
          {media, media.contents_used |> Enum.count() > 0}

        {:error, :not_found, _} = res ->
          res
      end
    end

    def get_platform(args), do: get(args, @platform_collection)
    def insert_platform(args), do: insert(args, @platform_collection)

    def update_platform(%MongoDB{args: %{"id" => _id} = args}),
      do: update_platform_common(args)

    def update_platform(%MongoDB{args: %{id: _id} = args}),
      do: update_platform_common(args)

    def update_platform_common(args) do
      id = Helpers.extract_param(args, :id)

      with {:ok, %Platform{} = platform} <- get(%MongoDB{args: id}, @platform_collection),
           data <- Platform.changeset(platform, args),
           {_data, true} <- {data, data.valid?} do
        update(data, id, @platform_collection)
      else
        {:error, :not_found, _collection} ->
          {:error, %{error: "#{@platform_collection} does not exist"}}

        {data, false} ->
          ## TO DO we should cover this to return a proper error in case the changeset
          ## is not valid
          {:error, data}
      end
    end

    def delete_platform(%MongoDB{args: id} = args) do
      with true <- Helpers.valid_object_id?(id), false <- platform_used?(id) do
        delete(args, @platform_collection)
      else
        {:error, :not_found, _message} = res ->
          res

        true ->
          {:error, gettext("This platform cannot be deleted as it used by medias.")}

        false ->
          {:error, Helpers.id_error_message(id)}
      end
    end

    def platform_used?(id) do
      id = ObjectId.decode!(id)

      pipeline = [%{"$match" => %{"_id" => id}}] ++ join_pipe_platform()

      result =
        Mongo.aggregate(Helpers.repo(), @platform_collection, pipeline)
        |> Enum.to_list()
        |> Enum.at(0)

      case result do
        nil ->
          {:error, :not_found, "#{@platform_collection |> String.capitalize()} does not exist"}

        %{"number_of_medias" => 0} ->
          false

        %{"number_of_medias" => _} ->
          true
      end
    end

    def get_media(%MongoDB{args: id}) do
      with true <- Helpers.valid_object_id?(id), %{total: 0} <- get_full_media(id) do
        {:error, :not_found, @media_collection |> String.capitalize()}
      else
        %{result: result} ->
          {:ok, result |> List.first() |> Helpers.check_files_privacy()}

        false ->
          {:error, Helpers.id_error_message(id)}
      end
    end

    def get(%MongoDB{args: id}, collection) do
      case Mongo.find_one(:mongo, collection, %{
             _id: Helpers.convert_to_object_id(id)
           }) do
        nil ->
          {:error, :not_found, collection |> String.capitalize()}

        item ->
          {:ok, Helpers.format_item(item, schema_to_module(collection), id)}
      end
    end

    def get_full_media(id) do
      id = ObjectId.decode!(id)

      initial_pipeline = [
        %{"$match" => %{"_id" => id}}
      ]

      query_collection(@media_collection, number_of_contents() ++ initial_pipeline, join_pipe())
    end

    ## additional pipies contain the join pipes
    def query_collection(
          collection,
          filters_pipe,
          additional_pipes \\ [],
          sort_pipe \\ [],
          pagintaion_pipe \\ []
        ) do
      ## I had to put the join pipes first as the other pipes might depend on its result in some cases
      pipes =
        additional_pipes ++
          filters_pipe ++
          pagintaion_pipe ++
          sort_pipe

      pipes =
        if Enum.all?(pipes, &(&1 == [])),
          do: [%{"$project" => %{"include_all" => 0}}],
          else: pipes

      pipeline = [
        %{
          "$facet" => %{
            "result" => pipes,
            "total" => additional_pipes ++ filters_pipe ++ [%{"$count" => "count"}]
          }
        }
      ]

      %{"result" => result, "total" => total} =
        Mongo.aggregate(Helpers.repo(), collection, pipeline)
        |> Enum.to_list()
        |> Enum.at(0)

      # total =

      %{
        result:
          Helpers.format_result(
            result,
            schema_to_module(collection)
          ),
        total: total |> Enum.at(0, %{}) |> Map.get("count", 0)
      }
    end

    # defp handle_count(collection, filter) do
    #   case Mongo.count_documents(Helpers.repo(), collection, filter) do
    #     {:ok, count} when is_integer(count) ->
    #       count

    #     {:error, _} ->
    #       0

    #     _ ->
    #       0
    #   end
    # end

    defp media_by_id(id) do
      Mongo.find_one(Helpers.repo(), @media_collection, %{_id: ObjectId.decode!(id)})
      |> case do
        nil -> {:error, :not_found, @media_collection}
        item -> {:ok, item}
      end
    end

    def insert(%MongoDB{args: args}, collection) do
      module = schema_to_module(collection)
      # data = Media.changeset(%Media{}, args) equivalent to the line below
      data = apply(module, :changeset, [module |> struct(%{}), args |> Helpers.atomize_keys()])

      with true <- data.valid?,
           {:ok, result} <-
             Mongo.insert_one(
               Helpers.repo(),
               collection,
               Helpers.get_changes(data)
             ) do
        get(%MongoDB{args: ObjectId.encode!(result.inserted_id)}, collection)
      else
        {:error, %{write_errors: [%{"code" => 11_000}]}} ->
          {:error, "#{collection |> String.capitalize()} already exists"}

        false ->
          {:error, data}

        _err ->
          {:error, %{error: "Unknown DB Error"}}
      end
    end

    def update(data, id, collection) do
      case Mongo.update_one(
             Helpers.repo(),
             collection,
             %{_id: ObjectId.decode!(id)},
             %{
               "$set" =>
                 data
                 |> Helpers.get_changes()
                 |> Helpers.format_changes()
                 |> Helpers.update_timestamp()
             }
           ) do
        {:ok, _result} ->
          get(%MongoDB{args: id}, collection)

        _err ->
          {:error, %{error: "Unknown DB Error"}}
      end
    end

    def delete(%MongoDB{args: id}, collection) do
      Mongo.delete_one(Helpers.repo(), collection, %{_id: ObjectId.decode!(id)})
      |> case do
        {:ok, %{deleted_count: 1}} ->
          {:ok, "#{collection |> String.capitalize()} with id #{id} deleted successfully"}

        {:ok, %{deleted_count: 0}} ->
          {:error, "#{collection |> String.capitalize()} does not exist"}
      end
    end

    defp schema_to_module(collection) do
      @schema_collection[collection]
    end

    defp number_of_contents do
      [
        %{
          "$addFields" => %{"number_of_contents" => %{"$size" => "$contents_used"}}
        }
      ]
    end

    defp join_pipe_platform do
      [
        %{
          "$lookup" => %{
            "from" => "media",
            "localField" => "_id",
            "foreignField" => "files.platform_id",
            "as" => "medias"
          }
        },
        %{
          "$addFields" => %{"number_of_medias" => %{"$size" => "$medias"}}
        }
      ]
    end

    defp join_pipe do
      [
        %{
          "$lookup" => %{
            "from" => "platform",
            "localField" => "files.platform_id",
            "foreignField" => "_id",
            "as" => "platforms"
          }
        },
        %{
          "$addFields" => %{
            "files" => %{
              "$map" => %{
                "input" => "$files",
                "in" => %{
                  "$mergeObjects" => [
                    "$$this",
                    %{
                      "platform" => %{
                        "$arrayElemAt" => [
                          "$platforms",
                          %{
                            "$indexOfArray" => [
                              "$platforms._id",
                              "$$this.platform_id"
                            ]
                          }
                        ]
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      ]
    end
  end
end
