class CatalogDefault < ActiveRecord::Migration
  def change
    change_column :zuora_connect_app_instances, :catalog, :jsonb, default: {}
  end
end
