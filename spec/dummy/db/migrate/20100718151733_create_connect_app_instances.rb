class CreateConnectAppInstances < ActiveRecord::Migration
  def change
    if !ActiveRecord::Base.connection.table_exists?('zuora_connect_app_instances')
      create_table :zuora_connect_app_instances do |t|
        t.timestamps null: false
      end
    end
  end
end
