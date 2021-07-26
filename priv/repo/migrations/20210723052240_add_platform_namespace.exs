defmodule Media.Repo.Migrations.AddPlatformNamespace do
  use Ecto.Migration

  def change do
    alter table(:platform) do
      add(:namespace, :string)
    end
  end
end
