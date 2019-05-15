class AddCatalogAttemptedAt < ActiveRecord::Migration
  def change
    add_column :zuora_connect_app_instances, :catalog_update_attempt_at, :datetime  unless column_exists? :zuora_connect_app_instances, :catalog_update_attempt_at
  end
end
