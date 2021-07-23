defmodule MediaWeb.PlatformControllerTest do
  use MediaWeb.ConnCase
  alias Media.TestHelpers
  alias Media.{Helpers, S3Manager}
  import Mock

  setup_with_mocks([
    {Helpers, [:passthrough],
     youtube_video_details: fn _url ->
       %{"items" => [%{"contentDetails" => %{"duration" => "PT4M30S"}}]}
     end},
    {S3Manager, [:passthrough],
     upload_file: fn file_name, _path ->
       {:ok,
        %{
          bucket: Helpers.aws_bucket_name(),
          filename: "#{file_name <> TestHelpers.uuid()}",
          id: "#{TestHelpers.uuid()}",
          url: "some url"
        }}
     end,
     upload_thumbnail: fn file_name, _path ->
       {:ok,
        %{
          bucket: "aws_bucket_name",
          filename: "#{file_name <> TestHelpers.uuid()}",
          id: "#{TestHelpers.uuid()}",
          url: "some url"
        }}
     end,
     change_object_privacy: fn _file_name, _privacy ->
       {:ok, %{}}
     end,
     get_temporary_aws_credentials: fn _unique_id ->
       %{
         access_key: "access_key_id",
         secret_key: "secret_access_key",
         session_token: "session_token"
       }
     end,
     read_private_object: fn _credentials, _destination ->
       %{
         url: "private url",
         headers: %{}
       }
     end,
     delete_file: fn _filename ->
       {:ok, %{}}
     end}
  ]) do
    :ok
  end

  @valid_media_attrs %{
    author: "some author id",
    locked_status: "locked",
    private_status: "public",
    seo_tag: "some seo tag",
    tags: ["tag1", "tag2"],
    title: "some media title",
    type: "video"
  }
  @valid_attrs %{
    "description" => "some description",
    "height" => 42,
    "name" => "some name",
    "width" => 42,
    "namespace" => "some namespace"
  }
  @invalid_attrs %{description: nil, height: nil, name: nil, width: nil}
  @update_attrs %{
    "description" => "some updated description",
    "height" => 43,
    "name" => "some updated name",
    "width" => 43,
    "namespace" => "update namespace"
  }
  describe "PostgreSQL:" do
    test "POST /platform creates a platform", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      test_create_valid_platform()
    end

    test "POST /platform returns error when invalid data", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      test_invalid_platform_creation()
    end

    test "GET /platform/:id returns the platform", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")
      test_get_platform()
    end

    test "GET /platform/:id returns error when it doesn't exist", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")
      test_get_nonexisting_platform(0)
    end

    test "Delete /platform/:id deletes a platform", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      test_delete_platform()
    end

    test "Delete /platform/:id returns 404 when not found", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      test_delete_nonexisting_platform(0)
    end

    test "Delete /platform/:id returns 400 when invalid id", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      test_delete_invalid_id()
    end

    test "Put /platform/:id updates a platform", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      test_update_platform()
    end

    test "PUT /platform/:id returns error when invalid data", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")
      test_invalid_update_platform()
    end

    test "POST list_platforms returns all platforms (filtered)", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      test_platforms_filtered()
    end

    test "POST list_platforms  returns all platforms (not paginated)" do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      # with_mock Helpers, [:passthrough], repo: fn -> Media.Repo end do
      test_list_platforms()

      # end
    end

    test "POST /list_platforms  returns all platforms (paginated)" do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")
      test_list_platforms_pagination()
    end
  end

  describe "MongoDB:" do
    test "POST /platform creates a platform", %{conn: _conn} do
      test_create_valid_platform()
    end

    setup _context do
      TestHelpers.clean_mongodb()
      TestHelpers.set_repo(:mongo, "mongoDB")
    end

    test "POST /platform returns error when invalid data", %{conn: _conn} do
      test_invalid_platform_creation()
    end

    test "GET /platform/:id returns the platform", %{conn: _conn} do
      TestHelpers.set_repo(:mongo, "mongoDB")

      test_get_platform()
    end

    test "GET /platform/:id returns error when it doesn't exist", %{conn: _conn} do
      test_get_nonexisting_platform("012345678912345678901234")
    end

    test "Delete /platform/:id deletes a platform", %{conn: _conn} do
      test_delete_platform()
    end

    test "Delete /platform/:id returns 404 when not found", %{conn: _conn} do
      TestHelpers.set_repo(:mongo, "mongoDB")
      test_delete_nonexisting_platform("012345678901234567890123")
    end

    test "Delete /platform/:id returns 400 when invalid id", %{conn: _conn} do
      TestHelpers.set_repo(:mongo, "mongoDB")

      test_delete_invalid_id()
    end

    test "Put /platform/:id updates a platform", %{conn: _conn} do
      TestHelpers.set_repo(:mongo, "mongoDB")

      test_update_platform()
    end

    test "PUT /platform/:id returns error when invalid data", %{conn: _conn} do
      test_invalid_update_platform()
    end

    test "POST list_platforms returns all platforms (filtered)", %{conn: _conn} do
      test_platforms_filtered()
    end

    test "POST /list_platforms  returns all platforms (not paginated)" do
      # with_mock Helpers, [:passthrough], repo: fn -> Media.Repo end do
      test_list_platforms()
      # end
    end

    test "POST /list_platforms  returns all platforms (paginated)" do
      test_list_platforms_pagination()
    end
  end

  def platform_fixture(attrs \\ %{}) do
    {:ok, platform} =
      attrs
      |> Enum.into(@valid_attrs)
      |> Media.Context.insert_platform()

    platform
  end

  def create_platform(attrs \\ @valid_attrs) do
    conn = build_conn()

    post(
      conn,
      TestHelpers.routes().media_path(conn, :insert_platform),
      attrs
    )
  end

  def list_platforms(attrs \\ %{}) do
    conn = build_conn()

    post(
      conn |> put_req_header("content-type", "application/json"),
      TestHelpers.routes().media_path(conn, :list_platforms),
      attrs
    )
  end

  defp media_fixture(attrs \\ %{}) do
    {:ok, media} =
      attrs
      |> Enum.into(@valid_media_attrs)
      |> Media.Context.insert_media()

    media
  end

  def test_invalid_platform_creation do
    conn = create_platform(@invalid_attrs)

    assert json_response(conn, 422)
  end

  def test_create_valid_platform do
    conn = create_platform()

    assert resp = json_response(conn, 200)
    assert @valid_attrs |> Map.put("id", resp["id"]) |> Map.put("number_of_medias", 0) == resp

    conn =
      get(
        conn,
        TestHelpers.routes().media_path(conn, :get_platform, resp["id"])
      )

    assert json_response(conn, 200)
  end

  def test_get_platform do
    conn = build_conn()
    platform = platform_fixture()

    conn =
      get(
        conn,
        TestHelpers.routes().media_path(conn, :get_platform, platform.id)
      )

    assert response = json_response(conn, 200)
    assert response["name"] == platform.name
    assert response["width"] == platform.width
    assert response["height"] == platform.height
    assert response["description"] == platform.description
    assert response["id"] == platform.id
  end

  def test_get_nonexisting_platform(id) do
    conn = build_conn()

    conn =
      get(
        conn,
        TestHelpers.routes().media_path(conn, :get_platform, id)
      )

    assert json_response(conn, 404)
  end

  def test_delete_platform do
    conn = create_platform()

    assert resp = json_response(conn, 200)
    id = resp["id"]
    assert @valid_attrs |> Map.put("id", id) |> Map.put("number_of_medias", 0) == resp
    conn1 = build_conn()

    conn1 =
      get(
        conn1,
        TestHelpers.routes().media_path(conn1, :get_platform, id)
      )

    assert %{"id" => ^id} = json_response(conn1, 200)

    conn2 = build_conn()

    conn2 =
      delete(
        conn2,
        TestHelpers.routes().media_path(conn2, :delete_platform, id)
      )

    assert json_response(conn2, 200)
    conn3 = build_conn()

    conn3 =
      get(
        conn3,
        TestHelpers.routes().media_path(conn3, :get_platform, id)
      )

    assert json_response(conn3, 404)
  end

  def test_delete_nonexisting_platform(id) do
    conn = build_conn()

    conn =
      delete(
        conn,
        TestHelpers.routes().media_path(conn, :delete_platform, id)
      )

    assert json_response(conn, 404)
  end

  def test_delete_invalid_id do
    conn = build_conn()

    conn =
      delete(
        conn,
        TestHelpers.routes().media_path(conn, :delete_platform, "invalid id")
      )

    assert json_response(conn, 400)
  end

  def test_update_platform do
    conn = create_platform()

    assert resp = json_response(conn, 200)
    id = resp["id"]
    assert @valid_attrs |> Map.put("id", id) |> Map.put("number_of_medias", 0) == resp

    conn1 = build_conn()

    conn1 =
      put(
        conn1,
        TestHelpers.routes().media_path(conn1, :update_platform, id),
        @update_attrs
      )

    assert resp = json_response(conn1, 200)
    assert @update_attrs |> Map.put("id", id) |> Map.put("number_of_medias", 0) == resp
  end

  def test_invalid_update_platform do
    conn = create_platform()
    assert resp = json_response(conn, 200)
    id = resp["id"]
    assert @valid_attrs |> Map.put("id", id) |> Map.put("number_of_medias", 0) == resp
    assert json_response(conn, 200)

    conn1 = build_conn()

    conn1 =
      put(
        conn1,
        TestHelpers.routes().media_path(conn1, :update_platform, id),
        @invalid_attrs
      )

    assert json_response(conn1, 422)
  end

  def test_platforms_filtered do
    conn = create_platform(@valid_attrs)
    assert platform = json_response(conn, 200)

    conn =
      create_platform(
        @valid_attrs
        |> Map.merge(%{"name" => "name-#{TestHelpers.uuid()}", "width" => 100, "height" => 200})
      )

    assert platform2 = json_response(conn, 200)

    image_file = [
      %{
        file: %Plug.Upload{
          path: "test/fixtures/phoenix.png",
          filename: "phoenix.png",
          content_type: "image/png"
        },
        platform_id: platform["id"]
      }
    ]

    files = [
      %{file: %{url: "https://www.youtube.com/watch?v=3HkggxR_kvE"}, platform_id: platform["id"]}
    ]

    media_fixture(%{files: files})

    media_fixture(%{
      files: image_file,
      title: "Media Title 1",
      type: "image"
    })

    media_fixture(%{files: files, title: "Media Title 2"})

    ## FILTER BY NAME
    platform_id = platform["id"]
    platform_name = platform["name"]

    conn = list_platforms(~s'{"filters": [{"key": "name", "value": "#{platform_name}"}]}')

    assert %{"result" => [%{"id" => ^platform_id, "name" => ^platform_name}], "total" => 1} =
             json_response(conn, 200)

    platform2_id = platform2["id"]
    platform2_name = platform2["name"]
    ## FILTER BY HEIGHT
    conn = list_platforms(~s'{"filters": [{"key": "height", "value": 200}]}')

    assert %{"result" => [%{"id" => ^platform2_id, "name" => ^platform2_name}], "total" => 1} =
             json_response(conn, 200)

    ## FILTER BY WITDH
    conn = list_platforms(~s'{"filters": [{"key": "width", "value": 100}]}')

    assert %{"result" => [%{"id" => ^platform2_id, "name" => ^platform2_name}], "total" => 1} =
             json_response(conn, 200)

    ## number of contents
    conn =
      list_platforms(~s'{"filters": [{"key": "number_of_medias", "value": 3, "operation": "="}]}')

    assert %{
             "result" => [
               %{"id" => ^platform_id, "name" => ^platform_name, "number_of_medias" => 3}
             ],
             "total" => 1
           } = json_response(conn, 200)

    conn =
      list_platforms(~s'{"filters": [{"key": "number_of_medias", "value": 3, "operation": ">"}]}')

    assert %{
             "result" => [],
             "total" => 0
           } = json_response(conn, 200)

    conn =
      list_platforms(~s'{"filters": [{"key": "number_of_medias", "value": 4, "operation": "<"}]}')

    assert %{
             "result" => _args,
             "total" => 2
           } = json_response(conn, 200)

    conn =
      list_platforms(~s'{"filters": [{"key": "number_of_medias", "value": 3, "operation": "<"}]}')

    assert %{
             "result" => [
               %{"id" => ^platform2_id, "name" => ^platform2_name, "number_of_medias" => 0}
             ],
             "total" => 1
           } = json_response(conn, 200)

    conn =
      list_platforms(
        ~s'{"filters": [{"key": "number_of_medias", "value": 3, "operation": "<="}]}'
      )

    assert %{
             "result" => args,
             "total" => 2
           } = json_response(conn, 200)

    assert args |> Enum.count() == 2
  end

  def test_list_platforms do
    conn = create_platform()
    assert platform = json_response(conn, 200)
    platform_id = platform["id"]
    height = platform["height"]
    width = platform["width"]

    conn = list_platforms()

    assert %{
             "result" => [
               %{
                 "description" => "some description",
                 "height" => ^height,
                 "id" => ^platform_id,
                 "name" => "some name",
                 "number_of_medias" => 0,
                 "width" => ^width
               }
             ],
             "total" => 1
           } = json_response(conn, 200)
  end

  def test_list_platforms_pagination do
    conn = create_platform()
    assert platform0 = json_response(conn, 200)
    conn = create_platform(@valid_attrs |> Map.merge(%{"name" => TestHelpers.uuid()}))
    assert platform1 = json_response(conn, 200)
    conn = create_platform(@valid_attrs |> Map.merge(%{"name" => TestHelpers.uuid()}))
    assert platform2 = json_response(conn, 200)

    platform0_id = platform0["id"]
    platform0_name = platform0["name"]

    conn = list_platforms(%{per_page: 1, page: 1, sort: %{"id" => "asc"}})

    assert %{
             "result" => [%{"id" => ^platform0_id, "name" => ^platform0_name}] = args,
             "total" => 3
           } = json_response(conn, 200)

    assert Enum.count(args) == 1
    platform1_id = platform1["id"]
    platform1_name = platform1["name"]

    conn = list_platforms(%{per_page: 1, page: 2, sort: %{"id" => "asc"}})

    %{"result" => [%{"id" => ^platform1_id, "name" => ^platform1_name}] = args, "total" => 3} =
      json_response(conn, 200)

    assert Enum.count(args) == 1
    platform2_id = platform2["id"]
    platform2_name = platform2["name"]
    conn = list_platforms(%{per_page: 1, page: 3, sort: %{"id" => "asc"}})

    %{"result" => [%{"id" => ^platform2_id, "name" => ^platform2_name}] = args, "total" => 3} =
      json_response(conn, 200)

    assert Enum.count(args) == 1
  end
end
