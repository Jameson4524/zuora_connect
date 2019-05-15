class AddNewApiToken < ActiveRecord::Migration
  def change
    add_column :zuora_connect_app_instances, :api_token, :string  unless column_exists? :zuora_connect_app_instances, :api_token
  end
end
