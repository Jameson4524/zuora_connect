class AddCatalogDataToAppInstance < ActiveRecord::Migration
  def change
    add_column :zuora_connect_app_instances, :catalog_updated_at, :datetime  unless column_exists? :zuora_connect_app_instances, :catalog_updated_at
    add_column :zuora_connect_app_instances, :catalog, :jsonb, default: {}  unless column_exists? :zuora_connect_app_instances, :catalog
  end
end
