defprotocol DB do
  @moduledoc false
  # "Accesses the configured databse. Supports for now MongoDB adn PostgreSQL"
  def get_media(struct)
  def list_medias(struct)
  def insert_media(struct)
  def update_media(struct)
  def delete_media(struct)
  def count_namespace(struct)
  def content_medias(struct)
  def dereference_content(struct)
  def list_platforms(struct)
  def get_platform(struct)
  def insert_platform(struct)
  def update_platform(struct)
  def delete_platform(struct)
end
