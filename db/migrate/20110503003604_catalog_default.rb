class CatalogDefault < ActiveRecord::Migration[5.0]
  def change
    change_column :zuora_connect_app_instances, :catalog, :jsonb, default: {}
  end
end
