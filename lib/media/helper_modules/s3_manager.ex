defmodule Media.S3Manager do
  @moduledoc """
    Amazon Web Services [AWS](https://aws.amazon.com) is an essential part of **Medias** Functionalities. In order to take advantage of all **Medias** features, you need to provide the needed AWS data.

    Media gives you the ability to secure your files if it contain sensitive infromation or to have a public access to your media. However, these files to be secured **Medias** need some data from you.
    This guide will show you the steps you need to follow to collect these values:

    - Login to AWS [Console](https://console.aws.amazon.com/console/home?region=us-east-1#).
    - Click on `services`
      - Go to the `security, Identity, & Compliance` section
      - Click on IAM
    - Click on `Users`
      - Click on `Add Users`.
      - Fill the `user name` and check the `Programmatic access` then click on the next permissions.
      - Click on `Attach Existing Policies Directly`
      - Search for `AmazonS3FullAccess` policy and check the box.
      - Click on `Create a new Policy`
        - Click on Choose a service
        - Search for `STS`.
        - Click on `STS` and check `all STS actions`.
        - Click on resources and check `specific` and check `any in this account` box for role.
        - Click Next Tags.
        - Click Next Preview.
        - Name your Policy (you will use it in later steps), write a description and click on `create Policy`
      - Go back to the create user window and hit the small refresh button on the right above the policies list.
      - Search for the name of the policy we creted and select it.
      - Click Next Tags.
      - Click Next Preview.
      - Click Create User.

    Now you will see you `access_key_id` and `secret_access_key`. These two are required by media so please save it somewhere safe. You also have the user ID of your account that shows at top right of your navbar (e.g. 4131-1613-5041) remove the dashes (-) and you will have now your third environemnt variable needed by *Medias**.

    All is left to do is to create a role. Now Go back to the IAM section, go to roles and click on `Create Role`

    - Choose Another AWS ACCOUNT
    - Put your user ID that we talked about before (e.g. `413116135041`)
    - Click `Next: Permissions`
    - Now choose the `AmazonS3FullAccess` and the other polici we created together
    - Click `Next: Tags`
    - Write the name of the role and fill a description
    - Create the role

    Now please retrieve the role name because this is what Medias needs.

    And we are done! 👏🏽

    To configure Medias data related to AWS:

    ```elixir
    config :medias,
      otp_app: :YOUR_APP_NAME,
      aws_iam_id: "413116135041",
      aws_access_key_id: "AKIAV3VNCU4*****",
      aws_secret_key: "VoF7GeK*****",
      aws_role_name: "role_test",
      aws_bucket_name: "eweevtestbucketprivate"
    ```
  """
  alias ExAws.{S3, S3.Upload, STS}
  alias Media.Helpers
  @doc false
  def upload_file(filename, path) do
    ext =
      filename
      |> Path.extname()

    filename = filename |> Path.basename(ext)

    aws_filename =
      "#{Application.get_env(:media, :otp_app)}/#{filename}#{ext |> unique_filename()}"

    ## for test mocking purposes
    __MODULE__.upload(path, aws_filename)
  end

  @doc false
  def upload_thumbnail(filename, path) do
    filename = thumbnail_filename(filename)

    __MODULE__.upload(path, filename)
  end

  @doc false
  def thumbnail_filename(filename) do
    path_list = filename |> Path.split()
    filename = path_list |> Enum.at(-1)
    ext = filename |> Path.extname()

    path_list
    |> List.replace_at(-1, "#{filename |> Path.basename(ext)}_thumbnail#{ext}")
    |> Path.join()
  end

  @doc false
  def upload(path, filename) do
    if Helpers.test_mode?() do
      aws =
        path
        |> Upload.stream_file()
        |> S3.upload(
          Helpers.aws_bucket_name(),
          filename,
          content_type: MIME.from_path(filename)
        )
        |> send_request()

      case aws.status_code do
        200 ->
          # File.rm!(filename)

          %{
            "CompleteMultipartUploadResult" => %{
              "Location" => url,
              "Key" => name,
              "ETag" => id,
              "Bucket" => bucket
            }
          } = aws.body |> XmlToMap.naive_map()

          {:ok, %{id: id, filename: name, url: url, bucket: bucket}}

        _ ->
          {:error, "Unable to upload file to amazon"}
      end
    else
      {:ok,
       %{
         id: "fake_file_id",
         filename: "fake_filename",
         url: "https://www.fake-url.com",
         bucket: "fake-bucket"
       }}
    end
  end

  @doc false
  def delete_file(path) do
    Helpers.aws_bucket_name()
    |> S3.delete_object(path)
    |> send_request()
  end

  @doc false
  def get_file(filename) do
    aws =
      Helpers.aws_bucket_name()
      |> S3.list_objects(prefix: filename)
      |> send_request()

    case aws.status_code do
      200 ->
        %{
          contents: contents
        } = aws.body

        fetch_file(contents)

      _ ->
        {:error, "File not found"}
    end
  end

  @doc false
  def fetch_file([]) do
    {:error, "File not found"}
  end

  @doc false
  def fetch_file(contents) do
    file = hd(contents)
    bucket = Helpers.aws_bucket_name()
    path = "https://s3.amazonaws.com/#{bucket}/#{file.key}"
    {:ok, %{id: file.e_tag, filename: file.key, path: path, bucket: bucket}}
  end

  @doc false
  defp unique_filename(extension) do
    UUID.uuid4(:hex) <> extension
  end

  @doc false
  def get_temporary_aws_credentials(profile_id) do
    resp =
      STS.assume_role(
        "arn:aws:iam::" <>
          Application.get_env(:media, :aws_iam_id) <>
          ":role/" <> Application.get_env(:media, :aws_role_name),
        "#{profile_id}"
      )

    case resp |> send_request() do
      %{body: body} ->
        %{
          access_key: body.access_key_id,
          secret_key: body.secret_access_key,
          session_token: body.session_token
        }

      error ->
        {:error, "#{inspect(error)}"}
    end
  end

  @doc false
  def send_request(req) do
    case ExAws.request(req, Helpers.aws_config()) do
      {:ok, response} -> response
      error -> error
    end
  end

  """
  This function toggles the object privacy.
  It takes the object key as a first argument and the new privacy status as a second argument
  The object key is the object filename.
  """

  @doc false
  def change_object_privacy(object_key, "public") do
    change_privacy(object_key, :public_read)
  end

  @doc false
  def change_object_privacy(object_key, "private") do
    change_privacy(object_key, :private)
  end

  @doc false
  def change_object_privacy(object_key, _) do
    change_privacy(object_key, :private)
  end

  defp change_privacy(object_key, acl_permission) do
    if Helpers.test_mode?() do
      {:ok,
       S3.put_object_acl(
         Application.get_env(:media, :aws_bucket_name),
         object_key,
         [{:acl, acl_permission}]
       )
       |> send_request()}
    else
      {:ok, :done}
    end
  end

  @doc false
  def read_private_object(credentials, destination) do
    ## We need to check the dependency plug_crypto there is a mismatch with OTP24
    url = "https://#{Helpers.aws_bucket_name()}.s3.amazonaws.com/#{destination}?Action=GetObject"
    headers = %{"X-Amz-Secure-Token" => credentials.session_token}

    {:ok, %{} = sig_data, _} =
      Sigaws.sign_req(url,
        region: Application.get_env(:media, :aws_region) || "us-east-1",
        service: "s3",
        headers: headers,
        access_key: Application.get_env(:media, :aws_access_key_id),
        secret: Application.get_env(:media, :aws_secret_key)
      )

    headers =
      Map.merge(headers, sig_data)
      |> Map.delete("X-Amz-SignedHeaders")
      |> Map.delete("X-Amz-Algorithm")

    %{url: url, headers: headers}
  end
end
