class AddCatalogMappingsToAppInstance < ActiveRecord::Migration
  def change
    add_column :zuora_connect_app_instances, :catalog_mapping, :jsonb, default: {} unless column_exists? :zuora_connect_app_instances, :catalog_mapping
  end
end
