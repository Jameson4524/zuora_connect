class AddExpirationToAppInstance < ActiveRecord::Migration[5.0]
  def change
    add_column :zuora_connect_app_instances, :oauth_expires_at, :datetime  unless column_exists? :zuora_connect_app_instances, :oauth_expires_at
  end
end
