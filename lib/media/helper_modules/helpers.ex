defmodule Media.Helpers do
  @moduledoc false
  import Ecto.Changeset
  import MediaWeb.Gettext

  alias BSON.ObjectId
  alias Ecto.Changeset
  alias Media.{Helpers, MongoDB, PostgreSQL, S3Manager}
  require Logger
  @media_collection "media"
  @platform_collection "platform"
  # Returns the router helper module from the configs. Raises if the router isn't specified.
  @spec router() :: atom()
  def router do
    case env(:router) do
      nil -> raise "The :router config must be specified: config :media, router: MyAppWeb.Router"
      r -> r
    end
    |> Module.concat(Helpers)
  end

  def env(key, default \\ nil) do
    Application.get_env(:media, key)
    |> case do
      nil -> default
      value -> value
    end
  end

  def aws_config do
    aws_key = env(:aws_access_key_id)
    aws_secret_key = env(:aws_secret_key)
    region = env(:aws_region, "us-east-1")
    if is_nil(aws_key) || is_nil(aws_secret_key), do: raise("
    Please make sure to provide a configuration for aws. e.g:
      config :media,
        aws_access_key_id: your_access_key_id,
        aws_secret_key: secret_access_key
    ")
    [access_key_id: aws_key, secret_access_key: aws_secret_key, region: region]
  end

  def active_database do
    Application.get_env(:media, :active_database)
    |> case do
      "mongoDB" ->
        %MongoDB{}

      "postgreSQL" ->
        %PostgreSQL{}

      _ ->
        raise "Please configure your active database for :media application, accepted values for :active_database are ``mongoDB`` or ``postgreSQL``"
    end
  end

  def aws_bucket_name do
    env(:aws_bucket_name)
    |> case do
      nil ->
        raise "Please make sure to configure your aws bucket to start uploading files."

      bucket_name ->
        bucket_name
    end
  end

  def repo do
    Application.get_env(:media, :repo)
    |> case do
      nil ->
        raise "Please make sure to configure your repo under for the :media app, i.e: repo: MyApp.Repo or if it is a mongoDB repo: :mongo where mongo is the name of the MongoDB application."

      repo ->
        repo
    end
  end

  def db_struct(args) do
    struct(active_database(), %{args: args |> Helpers.atomize_keys()})
  end

  def get_changes(data) do
    changes =
      data.changes
      |> Enum.reduce(%{}, fn change, acc ->
        change |> format_data_changes() |> Map.merge(acc)
      end)

    data.data
    |> format_data()
    |> Map.merge(changes)
    |> add_timestamps()
  end

  defp add_timestamps(data) when is_map(data) do
    creation_time = System.system_time(:second)
    Map.merge(data, %{inserted_at: creation_time, updated_at: creation_time})
  end

  def update_timestamp(data) when is_map(data) do
    Map.put(data, :updated_at, System.system_time(:second))
  end

  defp format_data(data) do
    data
    |> Map.from_struct()
    |> Map.drop([:__meta__])
  end

  defp format_data_changes(%{limit: limits} = changes) do
    limits =
      Enum.map(limits, fn limit ->
        limit |> Map.from_struct() |> Map.get(:changes)
      end)

    Map.put(changes, :limit, limits)
  end

  defp format_data_changes({key, value}) when is_list(value) do
    Map.put(
      %{},
      key,
      Enum.map(
        value,
        fn v ->
          if is_struct(v) do
            v.changes
          else
            v
          end
        end
      )
    )
  end

  defp format_data_changes({key, value}) when is_struct(value) do
    Map.put(%{}, key, value.changes)
  end

  defp format_data_changes({key, value}), do: Map.put(%{}, key, value)

  def format_changes(changes) do
    Enum.map(changes, &format_change/1) |> Enum.into(%{})
  end

  def format_change({field, %Ecto.Changeset{changes: _changes} = changeset}) do
    changeset
    |> format_change()
    |> (&Tuple.append({field}, &1)).()
  end

  def format_change(%Ecto.Changeset{changes: _changes} = changeset) do
    changeset
    |> Changeset.apply_changes()
    |> Map.from_struct()
    |> Map.drop([:id])
  end

  def format_change({field, data}) when is_list(data) do
    data
    |> Enum.map(&format_change/1)
    |> (&Tuple.append({field}, &1)).()
  end

  def format_change(field) do
    field
  end

  def format_item(item, schema, id) do
    {:ok, date_time} =
      (Map.get(item, "inserted_at") || Map.get(item, :inserted_at)) |> DateTime.from_unix()

    date = date_time |> DateTime.to_string() |> String.split(" ") |> hd

    struct(
      schema,
      item
      |> Morphix.atomorphiform!()
      |> Map.put(:id, id)
      |> Map.delete(:_id)
      |> Map.put(:inserted_at, date)
    )
  end

  def create_collections do
    Mongo.command(repo(), %{
      createIndexes: @media_collection,
      indexes: [
        %{key: %{author: 1}, name: "name_idx", unique: false},
        %{key: %{type: 1}, name: "type_idx", unique: false},
        %{key: %{contents_used: 1}, name: "contents_idx", unique: false},
        %{key: %{namespace: 1}, name: "namespace_idx", unique: false}
      ]
    })

    Mongo.command(repo(), %{
      createIndexes: @platform_collection,
      indexes: [
        %{key: %{name: 1}, name: "name_idx", unique: true}
      ]
    })
  end

  def format_result(result, schema) do
    result
    |> Enum.to_list()
    |> Enum.map(fn x ->
      converted_map = x |> Morphix.atomorphiform!()

      struct(
        schema,
        converted_map
        |> Map.put(:id, ObjectId.encode!(converted_map._id))
      )
    end)
  end

  @doc """
  Convert map string keys to :atom keys
  """
  def atomize_keys(nil), do: nil

  # Structs don't do enumerable and anyway the keys are already
  # atoms
  def atomize_keys(%{__struct__: _} = struct) do
    struct
  end

  def atomize_keys(%{} = map) do
    map
    |> Enum.map(fn {k, v} -> {atomize(k), atomize_keys(v)} end)
    |> Enum.into(%{})
  end

  # Walk the list and atomize the keys of
  # of any map members
  def atomize_keys([head | rest]) do
    [atomize_keys(head) | atomize_keys(rest)]
  end

  def atomize_keys(not_a_map) do
    not_a_map
  end

  defp atomize(k) when is_binary(k) do
    String.to_atom(k)
  end

  defp atomize(k) when is_atom(k) do
    k
  end

  def build_pagination(_offset, nil), do: {0, 0}

  def build_pagination(offset, limit) when is_integer(offset) and is_integer(limit) do
    offset = limit * (if(offset == 0, do: 1, else: offset) - 1)
    {offset, limit}
  end

  def build_pagination(offset, limit) when is_binary(offset) and is_binary(limit) do
    with {offset, _} <- Integer.parse(offset), {limit, _} <- Integer.parse(limit) do
      offset = limit * (if(offset == 0, do: 1, else: offset) - 1)
      {offset, limit}
    else
      _ -> {0, 0}
    end
  end

  def build_pagination(_offset, _limit), do: {0, 0}
  def extract_param(args, key, default \\ nil)

  def extract_param(args, key, default) when key |> is_binary,
    do: Map.get(args, key |> String.to_atom()) || Map.get(args, key) || default

  def extract_param(args, key, default) when key |> is_atom,
    do: Map.get(args, key) || Map.get(args, key |> Atom.to_string()) || default

  ### FILTERS HELPERS ###

  def build_params(params) do
    case build_args(params |> Helpers.atomize_keys()) do
      {:ok, new_args} ->
        {:ok, new_args}

      {:error, %{errors: errors}} ->
        {:error, message: gettext("Invalid data provided"), errors: errors}

      {:error, error} ->
        {:error, message: gettext("Invalid data provided"), errors: error}
    end
  end

  def build_args(args) do
    filters = extract_param(args, :filters, [])

    {new_filter, operation} = filters |> format_filter_post

    res = %{
      filter: new_filter,
      operation: operation,
      sort: args |> extract_param(:sort) |> build_sorts()
    }

    case res |> check_error_operation do
      :ok ->
        {:ok, res}

      :error ->
        {:error, gettext("Between operation should contain value and value2")}
    end
  end

  def check_error_operation(%{operation: op}) do
    # {_suc, error} = Enum.split_with(op, fn {_k, v} -> v != "error" end)
    result =
      Enum.any?(
        op,
        &Enum.any?(&1, fn {_k, v} -> v == "error" end)
      )

    if result do
      :error
    else
      :ok
    end
  end

  def format_filter_post(nil) do
    {[], []}
  end

  def format_filter_post(all_filters) when is_list(all_filters) do
    case all_filters do
      [] ->
        {[], %{}}

      _ ->
        # {[[]], [ops]}
        Enum.reduce(all_filters, {[], []}, fn filters, {filters_acc, ops_acc} ->
          {new_filters, new_o} = format_filters(filters)
          {filters_acc ++ [new_filters], List.insert_at(ops_acc, -1, new_o)}
        end)
    end
  end

  def format_filters(filters) do
    Enum.reduce(filters, {[], %{}}, fn filter, {fil, operation} ->
      {op, val} = get_op(filter)

      {
        if val != [] do
          key = filter |> extract_param("key")

          fil
          |> List.insert_at(
            -1,
            %{key => val}
          )
        else
          fil
        end,
        if op != nil do
          operation
          |> Map.put(extract_param(filter, "key"), op)
        else
          operation
        end
      }
    end)
  end

  defp get_op(filter) do
    op = extract_param(filter, :operation)
    val = extract_param(filter, :value)
    val2 = extract_param(filter, :value2)

    if op == "between" and (val == nil or val2 == nil) do
      {"error", val}
    else
      if op != "between",
        do: {%{"operation" => op}, val},
        else: {%{"operation" => op, "from" => val, "to" => val2}, val}
    end
  end

  def build_sorts(nil), do: nil
  def build_sorts(sorts) when sorts == %{}, do: nil

  def build_sorts(sorts) do
    res = sorts |> Enum.unzip()

    Enum.zip(res |> elem(0), res |> elem(1))
    |> Enum.into(%{}, &convert_sorts/1)
  end

  defp convert_sorts({_key, ""}) do
    nil
  end

  defp convert_sorts({"created", value}) do
    {"inserted_at", build_sort_value(value)}
  end

  defp convert_sorts({"updated", value}) do
    {"updated_at", build_sort_value(value)}
  end

  defp convert_sorts({key, value}) do
    {key, build_sort_value(value)}
  end

  defp build_sort_value(value) when value in ["desc", "DESC", "dsc", "DSC"] do
    "desc"
  end

  defp build_sort_value(value) when value in ["asc", "ASC"] do
    "asc"
  end

  defp build_sort_value(_value) do
    nil
  end

  def cartesian(key, value) do
    for i <- key,
        j <- value,
        do: %{i => j}
  end

  ### FILTERS HELPERS ###

  def binary_is_integer?(:error), do: false
  def binary_is_integer?({_duration, _}), do: true

  def valid_object_id?(id) when is_binary(id) do
    String.match?(id, ~r/^[0-9a-f]{24}$/)
  end

  def valid_object_id?(_id), do: false

  def valid_postgres_id?(id) when is_integer(id), do: {true, id}

  def valid_postgres_id?(id) when is_binary(id) do
    parsed = Integer.parse(id)
    integer? = binary_is_integer?(parsed)
    id = if integer?, do: parsed |> elem(0), else: -1
    {integer?, id}
  end

  def valid_postgres_id?(_id), do: {false, -1}

  def id_error_message(id),
    do: "The id provided: #{inspect(id)} is not valid. Please provide a valid ID."

  def delete_s3_files(files) when is_list(files) do
    delete_file_and_thumbnail(files)
  end

  def delete_s3_files(_files), do: :ok

  ## complete update does not support partial one
  ## all files will be replaced
  ## deleting those that are not and uploading new ones.
  def update_files(%Ecto.Changeset{valid?: false} = changeset, attrs),
    do: {changeset, attrs |> Map.delete(:files)}

  def update_files(%Ecto.Changeset{valid?: true} = changeset, attrs) do
    new_files = attrs |> extract_param(:files, %{})

    old_files = changeset |> get_field(:files) || []

    privacy =
      changeset |> get_field(:private_status) ||
        "private"

    type = changeset |> get_field(:type)

    old_ids = old_files |> Enum.map(&Map.get(&1, :file_id))

    case files_transaction(new_files, old_ids, %{privacy: privacy, type: type}) do
      {:ok, []} ->
        # if no new files are provided
        # then we don't want to update them so we keep the old files intact
        {changeset, attrs |> Map.put(:files, old_files)}

      {:ok, result} ->
        ## get new files and their ids
        new_files = result |> Enum.map(fn file -> file end)
        new_files_ids = new_files |> Enum.map(& &1.file_id)

        ## delete unused files
        Enum.filter(old_files, &(Map.get(&1, :file_id) not in new_files_ids))
        |> delete_file_and_thumbnail()

        # files_key = if Map.keys(attrs) |> Enum.any?(&(&1 |> is_atom)), do: :files, else: "files"
        ## we check
        attrs =
          attrs
          |> Map.put(
            :files,
            new_files
          )

        {changeset, attrs}

      {:error, error} ->
        {changeset |> add_error(:files, error), attrs |> Map.delete(:files)}
    end

    ## Check which files are removed
    ## if a file is removed deleted from S3
    ## if a file is updated remove the file and download a new one
    ## For comparision rely on ids
    # {files_to_delete, files_to_upload, files_to_persist}

    # ## upload files
    # Enum.each(files_to_upload, &S3Manager.upload_file(&1.filename, &1.path, aws_bucket_name()))
    # ## delete files

    ## return new files
    # Enum.each(files_to_delete, fn %{filename: filename} -> S3Manager.delete_file(filename), _video -> :ok end)
  end

  def rollback_changes(files) do
    ## Revert uploaded files
    delete_files(files)
    {:error, gettext("Error when uploading files")}
  end

  def delete_files(files_to_delete) do
    if Helpers.test_mode?(),
      do:
        Enum.each(files_to_delete, fn
          %{filename: filename} ->
            S3Manager.delete_file(filename)

          _video ->
            :ok
        end)
  end

  def delete_file_and_thumbnail(files_to_delete) do
    if Helpers.test_mode?(),
      do:
        Enum.each(files_to_delete, fn
          %{filename: nil} ->
            :ok

          %{filename: filename} ->
            S3Manager.delete_file(filename)

            S3Manager.delete_file(S3Manager.thumbnail_filename(filename))

          _ ->
            :ok
        end)
  end

  def files_transaction(new_files, _old_ids, %{type: type, privacy: privacy}) do
    Enum.reduce(new_files, {[], [], true, ""}, fn
      _file, {files, changes, false, error} ->
        {files, changes, false, error}

      file, {files, changes, true, _error} ->
        case upload_file(file, type, privacy) do
          {:ok, new_file, new_changes} ->
            {files ++ [new_file], changes ++ new_changes, true, ""}

          {:error, error, _new_changes} ->
            rollback_changes(changes)
            {files, changes, false, error}
        end
    end)
    |> case do
      {_files, _changes, false, error} ->
        {:error,
         gettext("Something went wrong when uploading your files. Reason:") <> " #{error}"}

      {files, _changes, true, _error} ->
        {:ok, files}
    end
  end

  def convert_base64_to_file(base64_file) when is_binary(base64_file) do
    case base64_file
         |> Base.decode64() do
      {:ok, file_binary} ->
        %{size: _size, filename: filename} = Helpers.get_base64_info(base64_file)

        {:ok, temp_dir} = Temp.mkdir("temp_dir")
        temp_path = temp_dir <> filename
        File.write(temp_path, file_binary)
        {:ok, %{path: temp_path, filename: filename, content_type: MIME.from_path(temp_path)}}

      _ ->
        {:error, gettext("Invalid binary file")}
    end
  end

  def convert_base64_to_file(_base64_file),
    do: {:error, gettext("The file sent is not a base64 file")}

  def upload_file(%{file_id: _file_id} = file, _type, _privacy), do: {:ok, file, []}

  ## base64_file should be a string
  def upload_file(
        %{base64: true, file: base64_file} = file,
        "image",
        privacy
      ) do
    case convert_base64_to_file(base64_file) do
      {:ok, converted_file} ->
        upload_image(file |> Map.put(:file, converted_file) |> Map.delete(:base64), privacy)

      {:error, error} ->
        {:error, error, []}
    end
  end

  def upload_file(
        %{file: %Plug.Upload{path: _path, content_type: "image/" <> _imagetype} = _file} =
          new_file,
        "image",
        privacy
      ) do
    upload_image(new_file, privacy)
  end

  def upload_file(%{file: %{url: _url}} = file, "video", _privacy) do
    handle_youtube_video(file)
  end

  def upload_image(%{file: %{path: path} = file} = new_file, privacy) do
    with {:ok, %{size: size}} <- File.stat(path),
         {:ok, %{bucket: _bucket, filename: filename, id: file_id, url: url} = base_file} <-
           S3Manager.upload_file(file.filename, file.path),
         {_file, {:ok, _}} <-
           {[base_file], S3Manager.change_object_privacy(filename, privacy)},
         ## create a temp directory that will get cleaned up at the end of this request
         tmp_path <- create_thumbnail(file.path),
         {_basefile, {:ok, %{filename: thumbnail_filename, url: thumbnail_url} = thumbnail_file}} <-
           {[base_file], S3Manager.upload_thumbnail(filename, tmp_path)},
         {_files, {:ok, _}} <-
           {[base_file] ++ [thumbnail_file],
            S3Manager.change_object_privacy(thumbnail_filename, privacy)} do
      {:ok,
       new_file
       |> Map.delete(:file)
       |> Map.merge(%{
         filename: filename,
         thumbnail_url: thumbnail_url,
         file_id: file_id,
         url: url,
         type: file.content_type,
         size: size
       }), [base_file, thumbnail_file]}
    else
      {files, {:error, error}} -> {:error, error, files}
      {:error, err} -> {:error, err, []}
    end
  end

  def upload_file(_, _, _privacy),
    do:
      {:error,
       gettext(
         "The file structure/type you provided is not supported. Hint: Make sure to provide a new file upload or an existing file URL."
       ), []}

  def youtube_endpoint do
    "https://www.googleapis.com/youtube/v3"
  end

  def get_youtube_id(url) do
    ## this is due to credo not accepting long line for regex so compiling it with a string passes
    ## the "i" is for case insensitive
    {:ok, valid_youtube_url?} =
      Regex.compile(
        "^(https?:\/\/)?((www\.)?(youtube(-nocookie)?|youtube.googleapis)\.com.*(v\/|v=|vi=|vi\/|e\/|embed\/|user\/.*\/u\/\d+\/)|youtu\.be\/)([_0-9a-z-]+)",
        "i"
      )

    if Regex.match?(
         valid_youtube_url?,
         url
       ) do
      {:ok, capture_id} =
        Regex.compile(
          "^(https?:\/\/)?((www\.)?(youtube(-nocookie)?|youtube.googleapis)\.com.*(v\/|v=|vi=|vi\/|e\/|embed\/|user\/.*\/u\/\d+\/)|youtu\.be\/)(?<id>[_0-9a-z-]+)",
          "i"
        )

      {:ok,
       Regex.named_captures(
         capture_id,
         url
       )}
    else
      {:error, :not_youtube_url}
    end
  end

  ## gets youtube details on the video using the api key and video id
  def youtube_video_details(video_id) do
    if Helpers.test_mode?() do
      endpoint_get_callback(
        "#{youtube_endpoint()}/videos?id=#{video_id}&key=#{env(:youtube_api_key)}&part=contentDetails"
      )
    else
      ## For testing purposes
      %{"items" => [%{"contentDetails" => %{"duration" => "PT03M30S"}}]}
    end
  end

  def endpoint_get_callback(
        url,
        headers \\ [{"content-type", "application/json"}]
      ) do
    case HTTPoison.get(url, headers) do
      {:ok, response} ->
        fetch_response_body(response)

      {:error, error} ->
        {:error, error}
    end
  end

  defp fetch_response_body(response) do
    case Poison.decode(response.body) do
      {:ok, body} ->
        body

      _ ->
        {:error, response.body}
    end
  end

  def handle_youtube_video(file) do
    video_file = extract_param(file, :file)
    url = extract_param(video_file, :url)

    with true <- is_binary(url),
         {:ok, %{"id" => video_id}} <- get_youtube_id(url),
         %{"items" => items} <-
           __MODULE__.youtube_video_details(url) do
      thumbnail_url = "https://img.youtube.com/vi/#{video_id}/default.jpg"

      details =
        items
        |> List.first() || %{}

      duration =
        details
        |> Map.get("contentDetails", %{})
        |> Map.get("duration", "PT0M0S")
        |> format_duration()

      {:ok,
       file
       |> Map.merge(%{
         duration: duration,
         file_id: video_id,
         url: url,
         type: "mp4",
         thumbnail_url: thumbnail_url
       })
       |> Map.delete(:file), []}
    else
      false ->
        {:error, gettext("Please provide a valid video url"), []}

      {:error, :not_youtube_url} ->
        {:error, gettext("This video is not a youtube video"), []}

      {:error, _} ->
        {:error, gettext("Could not fetch youtube video details"), []}
    end
  end

  # convert the youtube's duration representation to seconds
  defp format_duration(duration) do
    ## this will output ["1", "30", "40"] first one for hours second for minutes third for seconds
    list_of_time = String.splitter(duration, ["PT", "H", "M", "S"]) |> Enum.reject(&(&1 == ""))
    format_duration(list_of_time, :erlang.length(list_of_time))
  end

  defp format_duration(list_of_time, 1) do
    String.to_integer(List.first(list_of_time))
  end

  defp format_duration(list_of_time, 2) do
    String.to_integer(Enum.at(list_of_time, 0)) * 60 + String.to_integer(Enum.at(list_of_time, 1))
  end

  defp format_duration(list_of_time, 3) do
    String.to_integer(Enum.at(list_of_time, 0)) * 3600 +
      String.to_integer(Enum.at(list_of_time, 1)) * 60 +
      String.to_integer(Enum.at(list_of_time, 2))
  end

  def check_files_privacy(%{files: _files, private_status: "public"} = media), do: media

  def check_files_privacy(%{files: files, private_status: "private"} = media) do
    Map.put(media, :files, files |> Enum.map(&add_privacy_data(&1)))
  end

  def add_privacy_data(%{file_id: _id, filename: filename} = file) do
    ## get the headers and updated url for private files
    private_data =
      S3Manager.get_temporary_aws_credentials("#{UUID.uuid4(:hex) |> String.slice(0..12)}")
      |> S3Manager.read_private_object("#{Helpers.aws_bucket_name()}/#{filename}")

    Map.merge(file, private_data)
  end

  def create_thumbnail(path) do
    dir_path = Temp.mkdir!("tmp-dir")
    tmp_path = Path.join(dir_path, "thumbnail-#{UUID.uuid4()}.jpg")

    Thumbnex.create_thumbnail(path, tmp_path,
      max_width: 200,
      max_height: 200
    )

    tmp_path
  end

  # Helper functions to read the binary to determine the image extension
  defp image_extension(<<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>), do: ".png"
  defp image_extension(<<0xFF, 0xD8, _::binary>>), do: ".jpg"

  defp image_extension(_), do: ""

  def get_base64_info(file) do
    size = String.length(file)

    filename =
      file
      |> Base.decode64!()
      |> fetch_extension()
      |> unique_filename()

    %{filename: filename, size: size}
  end

  @doc false
  def unique_filename(extension) do
    UUID.uuid4(:hex) <> extension
  end

  defp fetch_extension(file) do
    file
    |> image_extension()
  end

  @doc """
  This functions checks the environment we are in and the test mode.
  If the test mode is real or the env is not :test it returns true
  false otherwise
  """
  def test_mode? do
    System.get_env("MEDIA_TEST") != "test" or
      (System.get_env("MEDIA_TEST") == "test" && Helpers.env(:test_mode, "real") == "real")
  end
end
