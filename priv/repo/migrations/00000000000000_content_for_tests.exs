defmodule Media.Repo.Migrations.ContentForTests do
  use Ecto.Migration

  if Media.Helpers.test_mode?(:database) do
    def change do
      create table(:content) do
        add(:title, :string)

        timestamps()
      end
    end
  end
end
