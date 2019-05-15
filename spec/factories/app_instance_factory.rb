# FactoryBot.define do
# 	factory :appinstance, class: ZuoraConnect::AppInstanceBase do
#         id 234550 
#         access_token SecureRandom.hex(32)
#         refresh_token SecureRandom.hex(32)
#         token SecureRandom.hex(32) 
#         oauth_expires_at Time.now + 1.month
#         api_token SecureRandom.hex(32) 
#         catalog_updated_at nil 
#         emails {["workflow@zuora.com"]} 
#         notes "Workflow Testing ENV - Taylor Medford" 
#         limits {{"tasks"=>"35000"}}
#         data_loaded true 
#         task_mode "Collections" 
#         environment "Sandbox" 
#         catalog_update_attempt_at nil

#         trait :expired do
#           oauth_expires_at Time.now - 1.month
#         end
# 	end
# end