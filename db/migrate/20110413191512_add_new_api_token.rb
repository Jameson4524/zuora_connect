class AddNewApiToken < ActiveRecord::Migration[5.0]
  def change
    add_column :zuora_connect_app_instances, :api_token, :string  unless column_exists? :zuora_connect_app_instances, :api_token
  end
end
