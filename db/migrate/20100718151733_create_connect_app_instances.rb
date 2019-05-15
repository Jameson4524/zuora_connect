class CreateConnectAppInstances < ActiveRecord::Migration[5.0]
  def change
    if !ActiveRecord::Base.connection.table_exists?('zuora_connect_app_instances')
      create_table :zuora_connect_app_instances do |t|
        t.timestamps null: false
      end
    end
  end
end
