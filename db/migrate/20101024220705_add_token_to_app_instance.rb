class AddTokenToAppInstance < ActiveRecord::Migration[5.0]
  def change
    add_column :zuora_connect_app_instances, :token, :string  unless column_exists? :zuora_connect_app_instances, :token
  end
end
