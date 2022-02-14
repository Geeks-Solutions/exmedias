defmodule Media.Repo.Migrations.ContentForTests do
  use Ecto.Migration
  alias Media.Helpers

  if System.get_env("MEDIA_TEST") == "test" do
    def change do
      create table(:content) do
        add(:title, :string)

        timestamps()
      end
    end
  end
end
