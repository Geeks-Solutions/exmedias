defmodule MediaWeb.MediaControllerTest do
  use MediaWeb.ConnCase
  alias Media.{Helpers, S3Manager, TestHelpers}
  alias Media.Test.Contents

  import Mock

  @valid_attrs %{
    "author" => "some author id",
    "locked_status" => "locked",
    "private_status" => "public",
    "seo_tag" => "some seo tag",
    "tags" => ["tag1", "tag2"],
    "title" => "some media title",
    "type" => "image",
    "namespace" => "test"
  }
  @invalid_attrs_author %{
    author: nil,
    locked_status: "locked",
    private_status: "public",
    seo_tag: "some seo tag",
    tags: ["tag1", "tag2"],
    title: "some media title",
    type: "video"
  }
  @invalid_attrs_type %{
    author: "some author id",
    locked_status: "locked",
    private_status: "public",
    seo_tag: "some seo tag",
    tags: ["tag1", "tag2"],
    title: "some media title",
    type: "what is this media?"
  }
  @invalid_attrs %{
    "title" => nil,
    "author" => nil,
    "locked_status" => nil,
    "private_status" => nil
  }
  @valid_platform_attrs %{
    "description" => "some description",
    "height" => 42,
    "name" => "some name",
    "width" => 42
  }
  @update_attrs %{
    "title" => "some updated title",
    "author" => "some updated author",
    "locked_status" => "unlocked",
    "private_status" => "public"
  }

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
          filename: "#{TestHelpers.uuid() <> file_name}",
          id: "#{TestHelpers.uuid()}",
          url: "some url"
        }}
     end,
     upload_thumbnail: fn file_name, _path ->
       {:ok,
        %{
          bucket: "aws_bucket_name",
          filename: "#{TestHelpers.uuid() <> file_name}",
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

  describe "PostgreSQL:" do
    test "GET /content/medias/:id return the media" do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      assert test_content_medias(0) |> Enum.count() == 0
      conn = create_media()

      assert resp = json_response(conn, 200)
      media_id_1 = resp["id"]
      {:ok, %{id: ^media_id_1} = media} = Media.Context.get_media(media_id_1)
      conn = create_media()

      assert resp = json_response(conn, 200)
      media_id_2 = resp["id"]
      {:ok, %{id: ^media_id_2} = media2} = Media.Context.get_media(media_id_2)

      {:ok, content} =
        Contents.create_content(%{title: "content#{TestHelpers.uuid()}", medias: [media, media2]})

      assert test_content_medias(content.id) |> Enum.count() == 2
    end

    test "POST /media creates a media (type image)", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      test_create_valid_media()
    end

    test "POST /media creates an invalid base64 media", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      create_invalid_base64()
    end

    test "POST /media creates a media (type video)", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      test_create_valid_media(@valid_attrs |> Map.put("type", "video"))
    end

    test "POST /media returns error and roll back changes", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      test_media_rollback()
    end

    test "POST /media returns error when invalid data (author)", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      test_invalid_media_creation_author()
    end

    test "POST /media returns error when invalid data(type)", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      test_invalid_media_creation_type()
    end

    test "GET /media/:id returns the media (public)", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")
      test_get_media()
    end

    test "GET /media/:id returns the media (private)", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")
      test_get_media(@valid_attrs |> Map.put("private_status", "private"))

      ## we make sure these are called when we ask for private media
      assert called(S3Manager.get_temporary_aws_credentials(:_))
      assert called(S3Manager.read_private_object(:_, :_))
    end

    test "GET /media/:id returns error when it doesn't exist", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")
      test_get_nonexisting_media(0)
    end

    test "GET /media/namespaced/:namespace", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")
      test_media_count()
    end

    test "Delete /media/:id deletes a media", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      test_delete_media()
      assert called(S3Manager.delete_file(:_))
    end

    test "Delete /media/:id deletes a media (that is already used)", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      test_delete_media_used()
    end

    test "Delete /media/:id returns 404 when not found", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      test_delete_nonexisting_media(0)
    end

    test "Delete /media/:id returns 400 when invalid id", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      test_delete_invalid_id()
    end

    test "Put /media updates a media", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      test_update_media()
    end

    test "Put /media updates a media update the files", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      test_update_media_files()
    end

    test "PUT /media/:id returns error when invalid data", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")
      test_invalid_update_media()
    end

    test "POST list_medias returns all platforms (filtered)", %{conn: _conn} do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      test_medias_filtered()
    end

    test "POST list_medias  returns all platforms (not paginated)" do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")

      test_list_medias()
    end

    test "POST /list_medias  returns all platforms (paginated)" do
      TestHelpers.set_repo(Media.Repo, "postgreSQL")
      test_list_medias_pagination()
    end
  end

  describe "MongoDB:" do
    test "GET /content/medias/:id return the media" do
      TestHelpers.set_repo(:mongo, "mongoDB")

      assert test_content_medias("012345678901234568901234") |> Enum.count() == 0
      conn = create_media()

      assert resp = json_response(conn, 200)
      media_id_1 = resp["id"]
      {:ok, %{id: ^media_id_1} = media} = Media.Context.get_media(media_id_1)
      conn = create_media()

      assert resp = json_response(conn, 200)
      media_id_2 = resp["id"]
      {:ok, %{id: ^media_id_2} = media2} = Media.Context.get_media(media_id_2)

      content_id =
        Contents.create_content(%{title: "content#{TestHelpers.uuid()}", medias: [media, media2]})

      conn1 = build_conn()

      conn1 =
        put(
          conn1,
          TestHelpers.routes().media_path(conn1, :update_media),
          @update_attrs
          |> Map.put("id", media_id_2)
          |> Map.put("files", %{"1" => resp["files"] |> Enum.at(0)})
          |> Map.put("contents_used", [content_id |> BSON.ObjectId.encode!()])
        )

      json_response(conn1, 200)

      assert test_content_medias(content_id |> BSON.ObjectId.encode!())
             |> Enum.count() == 1
    end

    test "POST /media creates a media", %{conn: _conn} do
      test_create_valid_media()
    end

    test "POST /media creates an invalid base64 media", %{conn: _conn} do
      TestHelpers.set_repo(:mongo, "mongoDB")

      create_invalid_base64()
    end

    test "POST /media returns error and roll back changes", %{conn: _conn} do
      TestHelpers.set_repo(:mongo, "mongoDB")

      test_media_rollback()
    end

    setup _context do
      TestHelpers.clean_mongodb()
      TestHelpers.set_repo(:mongo, "mongoDB")
    end

    test "POST /media returns error when invalid data", %{conn: _conn} do
      test_invalid_media_creation()
    end

    test "GET /media/:id returns the media", %{conn: _conn} do
      TestHelpers.set_repo(:mongo, "mongoDB")

      test_get_media()
    end

    test "GET /media/:id returns error when it doesn't exist", %{conn: _conn} do
      test_get_nonexisting_media("012345678912345678901234")
    end

    test "GET /media/namespaced/:namespace", %{conn: _conn} do
      TestHelpers.set_repo(:mongo, "mongoDB")
      test_media_count()
    end

    test "Delete /media/:id deletes a media", %{conn: _conn} do
      test_delete_media()
    end

    test "Delete /media/:id returns 404 when not found", %{conn: _conn} do
      TestHelpers.set_repo(:mongo, "mongoDB")
      test_delete_nonexisting_media("012345678901234567890123")
    end

    test "Delete /media/:id returns 400 when invalid id", %{conn: _conn} do
      TestHelpers.set_repo(:mongo, "mongoDB")

      test_delete_invalid_id()
    end

    test "Delete /media/:id deletes a media (that is already used)", %{conn: _conn} do
      TestHelpers.set_repo(:mongo, "mongoDB")

      test_delete_media_used()
    end

    test "Put /media/:id updates a media", %{conn: _conn} do
      TestHelpers.set_repo(:mongo, "mongoDB")

      test_update_media()
    end

    test "PUT /media/:id returns error when invalid data", %{conn: _conn} do
      test_invalid_update_media()
    end

    test "POST list_medias returns all platforms (filtered)", %{conn: _conn} do
      test_medias_filtered()
    end

    test "POST /list_medias  returns all platforms (not paginated)" do
      # with_mock Helpers, [:passthrough], repo: fn -> Media.Repo end do
      test_list_medias()
      # end
    end

    test "POST /list_medias  returns all platforms (paginated)" do
      test_list_medias_pagination()
    end
  end

  def platform_fixture(attrs \\ %{}) do
    {:ok, media} =
      attrs
      |> Enum.into(@valid_platform_attrs)
      |> Media.Context.insert_platform()

    media
  end

  def create_media(attrs \\ @valid_attrs) do
    files = create_files(attrs)
    conn = build_conn()

    post(
      conn,
      TestHelpers.routes().media_path(conn, :insert_media),
      attrs |> Map.put("files", files)
    )
  end

  def create_invalid_base64 do
    platform = platform_fixture(%{"name" => "#{TestHelpers.uuid()}"})
    conn = build_conn()

    conn =
      post(
        conn,
        TestHelpers.routes().media_path(conn, :insert_media),
        @valid_attrs
        |> Map.put(
          "files",
          %{
            "1" => %{
              "file" => "test/fixtures/phoenix.png",
              "platform_id" => platform.id,
              "base64" => true
            }
          }
        )
      )

    assert json_response(conn, 422)
  end

  def list_medias(attrs \\ %{}) do
    conn = build_conn()

    post(
      conn |> put_req_header("content-type", "application/json"),
      TestHelpers.routes().media_path(conn, :list_medias),
      attrs
    )
  end

  def test_invalid_media_creation_author do
    conn = create_media(@invalid_attrs_author)

    assert %{"errors" => %{"author" => _}} = json_response(conn, 422)
  end

  def test_invalid_media_creation_type do
    conn = create_media(@invalid_attrs_type)

    assert %{"errors" => %{"type" => _}} = json_response(conn, 422)
  end

  def test_invalid_media_creation do
    conn = create_media(@invalid_attrs_author)

    assert %{"errors" => %{"author" => _}} = json_response(conn, 422)
  end

  def test_create_valid_media(attrs \\ @valid_attrs) do
    conn = create_media(attrs)

    assert resp = json_response(conn, 200)

    case attrs["type"] do
      "image" ->
        assert %{
                 "id" => _id,
                 "author" => "some author id",
                 "locked_status" => "locked",
                 "private_status" => "public",
                 "seo_tag" => "some seo tag",
                 "tags" => ["tag1", "tag2"],
                 "title" => "some media title",
                 "type" => "image",
                 "files" => [
                   %{
                     "file_id" => _fileid,
                     "filename" => _filename,
                     "platform_id" => _1598,
                     "size" => _13900,
                     "type" => _,
                     "url" => _url,
                     "thumbnail_url" => _thumbnail_url
                   },
                   %{
                     "file_id" => _fileidbase64,
                     "filename" => _filenamease64,
                     "platform_id" => _1599,
                     "size" => _13901,
                     "type" => _typease64,
                     "url" => _urlase64,
                     "thumbnail_url" => _thumbnail_urlase64
                   }
                 ]
               } = resp

      "video" ->
        assert %{
                 "id" => _id,
                 "author" => "some author id",
                 "locked_status" => "locked",
                 "private_status" => "public",
                 "seo_tag" => "some seo tag",
                 "tags" => ["tag1", "tag2"],
                 "title" => "some media title",
                 "type" => "video",
                 "files" => [
                   %{
                     "file_id" => _fileid,
                     "filename" => _filename,
                     "platform_id" => _1598,
                     "size" => _13900,
                     "type" => _,
                     "url" => _url,
                     "thumbnail_url" => _thumbnail_url
                   }
                 ]
               } = resp
    end
  end

  def test_get_media(attrs \\ @valid_attrs) do
    conn = create_media(attrs)

    assert media = json_response(conn, 200)

    conn =
      get(
        conn,
        TestHelpers.routes().media_path(conn, :get_media, media["id"])
      )

    privacy = attrs |> Map.get("private_status")

    assert %{
             "author" => "some author id",
             "files" => [
               %{
                 "file_id" => _fileid1,
                 "filename" => _filename_fileid1,
                 "platform" => %{
                   "description" => "some description",
                   "height" => 42,
                   "id" => _16091,
                   "inserted_at" => _date11,
                   "name" => _name,
                   "updated_at" => _date2,
                   "width" => 42
                 },
                 "platform_id" => _1610,
                 "size" => _13900,
                 "type" => "image/png",
                 "thumbnail_url" => _thumbnail_url,
                 "url" => url
               },
               %{
                 #  "duration" => nil,
                 "file_id" => _fileid,
                 "filename" => _filename_fileid,
                 "platform" => %{
                   "description" => "some description",
                   "height" => 42,
                   "id" => _1609,
                   "inserted_at" => _date1,
                   "name" => _name,
                   "updated_at" => _date2,
                   "width" => 42
                 },
                 "platform_id" => _1610,
                 "size" => _13900,
                 "type" => "image/png",
                 "thumbnail_url" => _thumbnail_url,
                 "url" => url
               } = file
             ],
             "id" => _1075,
             #  "inserted_at" => _inserted,
             "locked_status" => "locked",
             "number_of_contents" => 0,
             "private_status" => ^privacy,
             "seo_tag" => "some seo tag",
             "tags" => ["tag1", "tag2"],
             "title" => "some media title",
             "type" => "image"
             #  "updated_at" => _updated
           } = json_response(conn, 200)

    case privacy do
      "private" ->
        assert url == "private url"
        assert is_map(file |> Map.get("headers"))

      "public" ->
        assert url == "some url"
        assert is_nil(file |> Map.get("headers"))
    end
  end

  def test_get_nonexisting_media(id) do
    conn = build_conn()

    conn =
      get(
        conn,
        TestHelpers.routes().media_path(conn, :get_media, id)
      )

    assert json_response(conn, 404)
  end

  def test_delete_media_used do
    conn = create_media()

    assert resp = json_response(conn, 200)
    id = resp["id"]
    # conn1 = build_conn()

    # conn1 =
    #   get(
    #     conn1,
    #     TestHelpers.routes().media_path(conn1, :get_media, id)
    #   )
    {:ok, %{id: ^id} = media} = Media.Context.get_media(id)

    content_id =
      Contents.create_content(%{title: "content#{TestHelpers.uuid()}", medias: [media]})

    ## reference media for mongo
    if Application.get_env(:media, :repo) == :mongo do
      conn1 = build_conn()

      conn1 =
        put(
          conn1,
          TestHelpers.routes().media_path(conn1, :update_media),
          @update_attrs
          |> Map.put("id", id)
          |> Map.put("files", %{"1" => resp["files"] |> Enum.at(0)})
          |> Map.put("contents_used", [content_id |> BSON.ObjectId.encode!()])
        )

      json_response(conn1, 200)
    end

    # assert %{"id" => ^id} = json_response(conn1, 200)

    conn2 = build_conn()

    conn2 =
      delete(
        conn2,
        TestHelpers.routes().media_path(conn2, :delete_media, id)
      )

    assert %{"error" => _error} = json_response(conn2, 400)
    conn3 = build_conn()

    conn3 =
      get(
        conn3,
        TestHelpers.routes().media_path(conn3, :get_media, id)
      )

    assert json_response(conn3, 200)
  end

  def test_delete_media do
    conn = create_media()

    assert resp = json_response(conn, 200)
    id = resp["id"]
    conn1 = build_conn()

    conn1 =
      get(
        conn1,
        TestHelpers.routes().media_path(conn1, :get_media, id)
      )

    assert %{"id" => ^id} = json_response(conn1, 200)

    conn2 = build_conn()

    conn2 =
      delete(
        conn2,
        TestHelpers.routes().media_path(conn2, :delete_media, id)
      )

    assert json_response(conn2, 200)
    conn3 = build_conn()

    conn3 =
      get(
        conn3,
        TestHelpers.routes().media_path(conn3, :get_media, id)
      )

    assert json_response(conn3, 404)
  end

  def test_delete_nonexisting_media(id) do
    conn = build_conn()

    conn =
      delete(
        conn,
        TestHelpers.routes().media_path(conn, :delete_media, id)
      )

    assert json_response(conn, 404)
  end

  def test_delete_invalid_id do
    conn = build_conn()

    conn =
      delete(
        conn,
        TestHelpers.routes().media_path(conn, :delete_media, "invalid id")
      )

    assert json_response(conn, 400)
  end

  ## This tests the updates without changing the files
  def test_update_media do
    conn = create_media()

    assert resp = json_response(conn, 200)
    id = resp["id"]

    assert_called_exactly(S3Manager.upload_file(:_, :_), 2)
    assert_called_exactly(S3Manager.upload_thumbnail(:_, :_), 2)

    assert @valid_attrs |> Map.put("id", id) |> Map.put("number_of_contents", 0) ==
             resp |> Map.delete("files")

    conn1 = build_conn()

    conn1 =
      put(
        conn1,
        TestHelpers.routes().media_path(conn1, :update_media),
        @update_attrs
        |> Map.put("id", id)
        |> Map.put("files", %{"1" => resp["files"] |> Enum.at(0)})
      )

    assert resp = json_response(conn1, 200)

    updated_media =
      Map.merge(
        @valid_attrs,
        @update_attrs
        |> Map.put("id", id)
        |> Map.put("number_of_contents", 0)
        |> Map.put("files", resp["files"])
      )

    assert updated_media == resp
    ## two times due to the fact that we need to create the thumbnail
    ## so basically two calls to insert the media and 0 calls when we
    ## did update with the same files
    assert_called_exactly(S3Manager.upload_file(:_, :_), 2)
    assert_called_exactly(S3Manager.upload_thumbnail(:_, :_), 2)
  end

  def test_update_media_files do
    ## Create a media
    conn = create_media()
    assert resp = json_response(conn, 200)
    id = resp["id"]

    assert_called_exactly(S3Manager.upload_thumbnail(:_, :_), 2)
    assert_called_exactly(S3Manager.upload_file(:_, :_), 2)

    assert @valid_attrs |> Map.put("id", id) |> Map.put("number_of_contents", 0) ==
             resp |> Map.delete("files")

    ## creates new files
    new_files = create_files(@valid_attrs)

    ## udpate new files
    conn1 = build_conn()

    conn1 =
      put(
        conn1,
        TestHelpers.routes().media_path(conn1, :update_media),
        @update_attrs
        |> Map.put("id", id)
        |> Map.put("files", new_files)
      )

    assert updated = json_response(conn1, 200)

    updated_media =
      Map.merge(
        @valid_attrs,
        @update_attrs
        |> Map.put("id", id)
        |> Map.put("number_of_contents", 0)
        |> Map.put("files", updated["files"])
      )

    ## make sure the updated media has a different file id
    assert updated["files"] |> List.first() |> Map.get("file_id") !=
             resp["files"] |> List.first() |> Map.get("file_id")

    ## make sure the response is what we expected
    assert updated_media == updated
    ## two times due to the fact that we need to create the thumbnail
    ## so basically two calls to insert the media and 2 calls when we
    ## did update with different files
    assert_called_exactly(S3Manager.upload_file(:_, :_), 4)
    assert_called_exactly(S3Manager.upload_thumbnail(:_, :_), 4)

    ## Deleted the files that were initially created
    assert_called_exactly(S3Manager.delete_file(:_), 4)
  end

  def test_invalid_update_media do
    conn = create_media()
    assert resp = json_response(conn, 200)
    id = resp["id"]

    assert @valid_attrs
           |> Map.put("files", resp["files"])
           |> Map.put("id", id)
           |> Map.put("number_of_contents", 0) == resp

    assert json_response(conn, 200)

    conn1 = build_conn()

    conn1 =
      put(
        conn1,
        TestHelpers.routes().media_path(conn1, :update_media),
        @invalid_attrs
        |> Map.put("id", id)
      )

    assert json_response(conn1, 422)
  end

  def test_medias_filtered do
    create_media(
      @valid_attrs
      |> Map.merge(%{"title" => "Media Title 0", "type" => "video"})
    )

    conn1 =
      create_media(
        @valid_attrs
        |> Map.merge(%{
          "title" => "Media Title 1",
          "type" => "image",
          "locked_status" => "unlocked"
        })
      )

    assert media1 = json_response(conn1, 200)

    conn1 =
      create_media(
        @valid_attrs
        |> Map.merge(%{
          "title" => "Media Title 2",
          "private_status" => "private",
          "type" => "video"
        })
      )

    media2 = json_response(conn1, 200)

    ## FILTER BY TITLE
    media_id_2 = media2["id"]
    media_title_2 = media2["title"]
    conn = list_medias(~s'{"filters": [{"key": "title", "value": "Media Title 2"}]}')

    assert %{"result" => [%{"id" => ^media_id_2, "title" => ^media_title_2}], "total" => 1} =
             json_response(conn, 200)

    media_id_1 = media1["id"]
    media_title_1 = media1["title"]
    ## type of media
    conn = list_medias(~s'{"filters": [{"key": "type", "value": "image"}]}')

    assert %{"result" => [%{"id" => ^media_id_1, "title" => ^media_title_1}], "total" => 1} =
             json_response(conn, 200)

    ## number of contents
    conn =
      list_medias(~s'{"filters": [{"key": "number_of_contents", "value": 0, "operation": "="}]}')

    assert %{"result" => _res, "total" => 3} = json_response(conn, 200)

    ## filter by private_status

    conn = list_medias(~s'{"filters": [{"key": "private_status", "value": "private"}]}')

    assert %{"total" => 1} = json_response(conn, 200)

    ## filter by lock_status
    conn = list_medias(~s'{"filters": [{"key": "locked_status", "value": "unlocked"}]}')
    assert %{"total" => 1} = json_response(conn, 200)
  end

  def test_content_medias(id) do
    conn = build_conn()

    conn =
      get(
        conn |> put_req_header("content-type", "application/json"),
        TestHelpers.routes().media_path(conn, :content_medias, id)
      )

    assert res = json_response(conn, 200)
    res
  end

  def test_list_medias do
    conn = create_media()
    assert json_response(conn, 200)

    conn = list_medias()

    assert %{
             "result" => [
               %{
                 "author" => "some author id",
                 "locked_status" => "locked",
                 "number_of_contents" => 0,
                 "private_status" => "public",
                 "seo_tag" => "some seo tag",
                 "tags" => ["tag1", "tag2"],
                 "title" => "some media title",
                 "type" => "image"
               }
             ],
             "total" => 1
           } = json_response(conn, 200)
  end

  def test_media_count do
    conn = create_media()
    assert json_response(conn, 200)
    conn = create_media()
    assert json_response(conn, 200)
    namespace = "another namespace"
    conn = create_media(@valid_attrs |> Map.merge(%{"namespace" => namespace}))
    assert json_response(conn, 200)
    conn = build_conn()

    conn =
      get(
        conn |> put_req_header("content-type", "application/json"),
        TestHelpers.routes().media_path(conn, :count_namespace, "test")
      )

    assert %{"total" => 2} = json_response(conn, 200)

    conn = build_conn()

    conn =
      get(
        conn |> put_req_header("content-type", "application/json"),
        TestHelpers.routes().media_path(conn, :count_namespace, namespace)
      )

    assert %{"total" => 1} = json_response(conn, 200)

    conn = build_conn()

    conn =
      get(
        conn |> put_req_header("content-type", "application/json"),
        TestHelpers.routes().media_path(conn, :count_namespace, "non-existing-name-space")
      )

    assert %{"total" => 0} = json_response(conn, 200)
  end

  def test_list_medias_pagination do
    conn = create_media()
    assert media0 = json_response(conn, 200)
    conn = create_media(@valid_attrs |> Map.merge(%{"title" => TestHelpers.uuid()}))
    assert media1 = json_response(conn, 200)
    conn = create_media(@valid_attrs |> Map.merge(%{"title" => TestHelpers.uuid()}))
    assert media2 = json_response(conn, 200)

    media0_id = media0["id"]
    media0_name = media0["title"]

    conn = list_medias(%{"per_page" => 1, "page" => 1, "sort" => %{"id" => "asc"}})

    assert %{
             "result" => [%{"id" => ^media0_id, "title" => ^media0_name}] = args,
             "total" => 3
           } = json_response(conn, 200)

    assert Enum.count(args) == 1
    media1_id = media1["id"]
    media1_name = media1["title"]

    conn = list_medias(%{per_page: 1, page: 2, sort: %{"id" => "asc"}})

    %{"result" => [%{"id" => ^media1_id, "title" => ^media1_name}] = args, "total" => 3} =
      json_response(conn, 200)

    assert Enum.count(args) == 1
    media2_id = media2["id"]
    media2_name = media2["title"]
    conn = list_medias(%{per_page: 1, page: 3, sort: %{"id" => "asc"}})

    %{"result" => [%{"id" => ^media2_id, "title" => ^media2_name}] = args, "total" => 3} =
      json_response(conn, 200)

    assert Enum.count(args) == 1
  end

  def create_files(attrs) do
    platform = platform_fixture(%{"name" => "#{TestHelpers.uuid()}"})

    case attrs["type"] do
      "image" ->
        %{
          "1" => %{
            "file" => %Plug.Upload{
              path: "test/fixtures/phoenix.png",
              filename: "phoenix.png",
              content_type: "image/png"
            },
            "platform_id" => platform.id
          },
          "2" => %{
            "file" => "test/fixtures/phoenix.png" |> File.read!() |> Base.encode64(),
            "platform_id" => platform.id,
            "base64" => true
          }
        }

      "video" ->
        %{
          "1" => %{
            "file" => %{url: "https://www.youtube.com/watch?v=3HkggxR_kvE"},
            "platform_id" => platform.id
          }
        }

      _ ->
        %{}
    end
  end

  def test_media_rollback do
    ## create a platform
    platform = platform_fixture(%{"name" => "#{TestHelpers.uuid()}"})

    attrs =
      @valid_attrs
      |> Map.put(
        "files",
        files = %{
          "1" => %{
            "file" => %Plug.Upload{
              path: "test/fixtures/phoenix.png",
              filename: "phoenix.png",
              content_type: "image/png"
            },
            "platform_id" => platform.id
          },
          "2" => %{
            "file" => "non_valid_file",
            "platform_id" => platform.id
          }
        }
      )

    conn = build_conn()

    conn =
      post(
        conn,
        TestHelpers.routes().media_path(conn, :insert_media),
        attrs |> Map.put("files", files)
      )

    assert json_response(conn, 422)

    ## assert that the rollback deleted the two initial files that were downloaded
    assert_called_exactly(S3Manager.delete_file(:_), 2)
  end
end
