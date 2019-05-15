class AddTokensToAppInstance < ActiveRecord::Migration[5.0]
  def change
    add_column :zuora_connect_app_instances, :access_token, :string unless column_exists? :zuora_connect_app_instances, :access_token
    add_column :zuora_connect_app_instances, :refresh_token, :string unless column_exists? :zuora_connect_app_instances, :refresh_token
  end
end
