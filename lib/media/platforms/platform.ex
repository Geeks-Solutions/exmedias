defmodule Media.Platforms.Platform do
  @moduledoc """
  The **Platform** will describe where you will display your media.

  You can link your media to a platform in order to know display the correct media on the correct platform.

  Let's take an example where you upload two images one with ratio `100x100` and the other with ratio `400x400`. You need to display the first one on mobile while the latter on desktop.
  This is where the **Platform** comes in handy.

  An example of a **Platform** :
  ```elixir
  %{
    description: "This platform is used for laptops and PC consoles.",
    height: 42,
    id: 1,
    name: "Desktop",
    width: 42
  }
  ```

  """
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :name,
             :height,
             :width,
             :description,
             :number_of_medias,
             :id,
             :namespace
           ]}
  schema "platform" do
    field(:description, :string)
    field(:height, :integer)
    field(:name, :string)
    field(:namespace, :string)
    field(:width, :integer)
    field(:number_of_medias, :integer, virtual: true, default: 0)

    timestamps()
  end

  @doc false
  def changeset(platform, attrs) do
    platform
    |> cast(attrs, [:height, :width, :description, :name, :namespace])
    |> validate_required([:height, :width, :description, :name])
    |> unique_constraint([:name])
  end
end
