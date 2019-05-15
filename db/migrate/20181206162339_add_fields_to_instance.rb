class AddFieldsToInstance < ActiveRecord::Migration[5.0]
  def change
  	add_column :zuora_connect_app_instances, :name, :string, default: "" unless column_exists? :zuora_connect_app_instances, :name
  end
end
