FactoryBot.define do
  factory :appinstance, class: ZuoraConnect::AppInstanceBase do
    access_token SecureRandom.hex(32)
    refresh_token SecureRandom.hex(32)
    token SecureRandom.hex(32) 
    api_token SecureRandom.hex(32) 
    catalog_updated_at nil 
    catalog_update_attempt_at nil

    oauth_expires_at Time.now + 1.month

    trait :expired do
      oauth_expires_at Time.now - 1.month
    end
  end
end

require 'rails_helper'
require 'rake'

RSpec.describe ZuoraConnect, type: :model do
 
  connect_login_type_missing = {"id":1057772,"name":"min1","mode":"Collections","status":"Running","user":"Taylor Medford","execution_timezone":"","execution_interval":"","target_login":{"tenant_type":"Zuora","username":"tmedford_master@dchudy.sbx","url":"https://apisandbox.zuora.com/apps/services/a/80.0","status":"Active","oauth_client_id":"4dbb232e-67b1-41b7-b0a7-6cc1732ff974","oauth_secret":"QBpjg0Y53L59lsT=D2W8","authentication_type":"","custom_data":{},"entities":[{}],"login_entities":[]},"organizations":[],"options":[],"user_settings":{},"applications":[{"id":345,"name":"Billing Post Processor","status":"trial"}]}
  task_info4_redis = {}

  after do
    Redis.current.keys("*").map {|x| Redis.current.del(x)}
  end
  context 'Basic Login' do 
    #Basic auth logins 
    basic_one_entity = {"id":1057770,"name":"min1","mode":"Collections","status":"Running","user":"Taylor Medford","execution_timezone":"","execution_interval":"","target_login":{"tenant_type":"Zuora","username":"tmedford_master@dchudy.sbx","password":"myPassword", "url":"https://apisandbox.zuora.com/apps/services/a/80.0","status":"Active","authentication_type":"basic","custom_data":{},"entities":[{}],"login_entities":[]},"organizations":[],"options":[],"user_settings":{},"applications":[{"id":345,"name":"Billing Post Processor","status":"trial"}]}
    basic_one_entity_redis = {}
    basic_one_entity_redis["#{basic_one_entity['id']}::task_data"] = basic_one_entity
    basic_one_entity_redis["#{basic_one_entity['id']}::last_refresh"] = Time.now.to_i
    basic_one_entity_redis["appInstance"] = basic_one_entity['id']

    basic_one_entity_redis["#{basic_one_entity['id']}::target_login::current_session"] = "thisisacurrentseesion"           
    basic_one_entity_redis["#{basic_one_entity['id']}::target_login::bearer_token"] = nil  
    basic_one_entity_redis["#{basic_one_entity['id']}::target_login::oauth_session_expires_at"] = nil

    basic_one_entity_with_3_login = {"id":1057771,"name":"min1","mode":"Collections","status":"Running","user":"Taylor Medford","execution_timezone":"","execution_interval":"","target_login":{"tenant_type":"Zuora","username":"tmedford_master@dchudy.sbx","password":"myPassword","url":"https://apisandbox.zuora.com/apps/services/a/80.0","status":"Active","authentication_type":"basic","custom_data":{},"entities":[{"id":"2c92c0f861789e700161bde76f005327","name":"Daniel Chudy Minion","locale":"en_US","status":"Provisioned","entityId":"23356","parentId":"2c92c0f86179f24301619c0aecd727d3","tenantId":"23241","timezone":"America/Los_Angeles","displayName":"Minion Tenant 1"}],"login_entities":[{"id":"2c92c0f86179f24301619c0aecd727d3","name":"Global","locale":"en_US","status":"Provisioned","entityId":"23241","parentId":"","tenantId":"23241","timezone":"America/Los_Angeles","displayName":"Daniel Chudy Personal Sandbox"},{"id":"2c92c0f861789e700161bde76f005327","name":"Daniel Chudy Minion","locale":"en_US","status":"Provisioned","entityId":"23356","parentId":"2c92c0f86179f24301619c0aecd727d3","tenantId":"23241","timezone":"America/Los_Angeles","displayName":"Minion Tenant 1"},{"id":"2c92c0f96178a7ae0161bde895c51cdf","name":"minion2","locale":"en_US","status":"Provisioned","entityId":"23355","parentId":"2c92c0f86179f24301619c0aecd727d3","tenantId":"23241","timezone":"America/Los_Angeles","displayName":"Minion Tenant 2"}]},"organizations":[],"options":[],"user_settings":{},"applications":[{"id":345,"name":"Billing Post Processor","status":"trial"}]}
    basic_one_entity_with_3_login_redis = {}
    basic_one_entity_with_3_login_redis["#{basic_one_entity_with_3_login['id']}::task_data"] = basic_one_entity_with_3_login
    basic_one_entity_with_3_login_redis["#{basic_one_entity_with_3_login['id']}::last_refresh"] = Time.now.to_i
    basic_one_entity_with_3_login_redis["appInstance"] = basic_one_entity_with_3_login['id']

    basic_one_entity_with_3_login["target_login"]["login_entities"].pluck("id").each do |entity_id|
      basic_one_entity_with_3_login_redis["#{basic_one_entity_with_3_login['id']}::#{entity_id}::target_login::current_session"] = "find_a_way_to_put_in_unique_data_per_entity"           
      basic_one_entity_with_3_login_redis["#{basic_one_entity_with_3_login['id']}::#{entity_id}::target_login::bearer_token"] = "nsjjed-345td-2erds2-34"   
      basic_one_entity_with_3_login_redis["#{basic_one_entity_with_3_login['id']}::#{entity_id}::target_login::oauth_session_expires_at"] = Time.now.to_i + 1.hour
    end

    basic_two_entity_with_3_login = {"id":1057773,"name":"sfffs","mode":"Collections","status":"Running","user":"Taylor Medford", "execution_timezone": "", "execution_interval": "", "target_login": { "tenant_type": "Zuora", "username": "tmedford_master@dchudy.sbx", "password":"myPassword", "url": "https://apisandbox.zuora.com/apps/services/a/80.0", "status": "Active", "authentication_type": "basic", "custom_data": {}, "entities": [ { "id": "2c92c0f86179f24301619c0aecd727d3", "name": "Global", "locale": "en_US", "status": "Provisioned", "entityId": "23241", "parentId": " ", "tenantId": "23241", "timezone": "America/Los_Angeles", "displayName": "Daniel Chudy Personal Sandbox" }, { "id": "2c92c0f861789e700161bde76f005327", "name": "Daniel Chudy Minion", "locale": "en_US", "status": "Provisioned", "entityId": "23356", "parentId": "2c92c0f86179f24301619c0aecd727d3", "tenantId": "23241", "timezone": "America/Los_Angeles", "displayName": "Minion Tenant 1" } ], "login_entities": [ { "id": "2c92c0f86179f24301619c0aecd727d3", "name": "Global", "locale": "en_US", "status": "Provisioned", "entityId": "23241", "parentId": " ", "tenantId": "23241", "timezone": "America/Los_Angeles", "displayName": "Daniel Chudy Personal Sandbox" }, { "id": "2c92c0f861789e700161bde76f005327", "name": "Daniel Chudy Minion", "locale": "en_US", "status": "Provisioned", "entityId": "23356", "parentId": "2c92c0f86179f24301619c0aecd727d3", "tenantId": "23241", "timezone": "America/Los_Angeles", "displayName": "Minion Tenant 1" }, { "id": "2c92c0f96178a7ae0161bde895c51cdf", "name": "minion2", "locale": "en_US", "status": "Provisioned", "entityId": "23355", "parentId": "2c92c0f86179f24301619c0aecd727d3", "tenantId": "23241", "timezone": "America/Los_Angeles", "displayName": "Minion Tenant 2" } ] }, "organizations": [], "options": [], "user_settings": { "timezone": "Eastern Time (US & Canada)", "local": "en", "id": 1 }, "applications": [ { "id": 345, "name": "Billing Post Processor", "status": "trial" }, { "id": 190, "name": "Workflow", "status": "trial" }, { "id": 447, "name": "Collections Manager - Collect", "status": "trial" } ] }
    basic_two_entity_with_3_login_redis = {}
    basic_two_entity_with_3_login_redis["#{basic_two_entity_with_3_login['id']}::task_data"] = basic_two_entity_with_3_login
    basic_two_entity_with_3_login_redis["#{basic_two_entity_with_3_login['id']}::last_refresh"] = Time.now.to_i
    basic_two_entity_with_3_login_redis["appInstance"] = basic_two_entity_with_3_login['id']

    basic_two_entity_with_3_login_redis["target_login"]["login_entities"].pluck("id").each do |entity_id|
      basic_two_entity_with_3_login_redis["#{basic_one_entity_with_3_login['id']}::#{entity_id}::target_login::current_session"] = "AsdaweaSCADS"       
      basic_two_entity_with_3_login_redis["#{basic_one_entity_with_3_login['id']}::#{entity_id}::target_login::bearer_token"] "asbkdahjkcsasbeareberbeabbear"     
      basic_two_entity_with_3_login_redis["#{basic_one_entity_with_3_login['id']}::#{entity_id}::target_login::oauth_session_expires_at"] = Time.now.to_i + 1.hour
    end

    context 'Without Redis Cache' do 
      before do 
        @basic_one_entity = connect_helper(task_info: basic_one_entity)
      end 

      it 'check class type' do
        expect(@oauth_one_entity.target_login.client.class).to eq(ZuoraAPI::Basic)
        expect(@oauth_one_entity_with_3_login.target_login.client.class).to eq(ZuoraAPI::Basic)
        expect(@oauth_two_entity_with_3_login.target_login.client.class).to eq(ZuoraAPI::Basic)
      end
    end 

    context 'With Redis Cache' do 
      before do 
        @basic_one_entity = connect_helper(task_info: basic_one_entity, task_redis_cache: basic_one_entity_redis) 
      end

      it 'check class type' do
        expect(@oauth_one_entity.target_login.client.class).to eq(ZuoraAPI::Basic)
        expect(@oauth_one_entity_with_3_login.target_login.client.class).to eq(ZuoraAPI::Basic)
        expect(@oauth_two_entity_with_3_login.target_login.client.class).to eq(ZuoraAPI::Basic)
      end
    end
  end 

  context 'Oauth Login' do 
    #Oauth Logins
    oauth_one_entity = {"id":1057769,"name":"min1","mode":"Collections","status":"Running","user":"Taylor Medford","execution_timezone":"","execution_interval":"","target_login":{"tenant_type":"Zuora","username":"tmedford_master@dchudy.sbx","url":"https://apisandbox.zuora.com/apps/services/a/80.0","status":"Active","oauth_client_id":"4dbb232e-67b1-41b7-b0a7-6cc1732ff974","oauth_secret":"QBpjg0Y53L59lsT=D2W8","authentication_type":"oauth","custom_data":{},"entities":[{}],"login_entities":[]},"organizations":[],"options":[],"user_settings":{},"applications":[{"id":345,"name":"Billing Post Processor","status":"trial"}]}
    oauth_one_entity_redis = {}
    oauth_one_entity_redis["#{oauth_one_entity['id']}::task_data"] = oauth_one_entity
    oauth_one_entity_redis["#{oauth_one_entity['id']}::last_refresh"] = Time.now.to_i
    oauth_one_entity_redis["appInstance"] = oauth_one_entity['id']

    oauth_one_entity_redis["#{oauth_one_entity['id']}::target_login:current_session"] = "WOOSHASDASd"         
    oauth_one_entity_redis["#{oauth_one_entity['id']}::target_login:bearer_token"] = "WADJSD"       
    oauth_one_entity_redis["#{oauth_one_entity['id']}::target_login:oauth_session_expires_at"] = Time.now.to_i + 1.hour

    oauth_one_entity_with_3_login = {"id":1057771,"name":"min1","mode":"Collections","status":"Running","user":"Taylor Medford","execution_timezone":"","execution_interval":"","target_login":{"tenant_type":"Zuora","username":"tmedford_master@dchudy.sbx","url":"https://apisandbox.zuora.com/apps/services/a/80.0","status":"Active","oauth_client_id":"4dbb232e-67b1-41b7-b0a7-6cc1732ff974","oauth_secret":"QBpjg0Y53L59lsT=D2W8","authentication_type":"oauth","custom_data":{},"entities":[{"id":"2c92c0f861789e700161bde76f005327","name":"Daniel Chudy Minion","locale":"en_US","status":"Provisioned","entityId":"23356","parentId":"2c92c0f86179f24301619c0aecd727d3","tenantId":"23241","timezone":"America/Los_Angeles","displayName":"Minion Tenant 1"}],"login_entities":[{"id":"2c92c0f86179f24301619c0aecd727d3","name":"Global","locale":"en_US","status":"Provisioned","entityId":"23241","parentId":"","tenantId":"23241","timezone":"America/Los_Angeles","displayName":"Daniel Chudy Personal Sandbox"},{"id":"2c92c0f861789e700161bde76f005327","name":"Daniel Chudy Minion","locale":"en_US","status":"Provisioned","entityId":"23356","parentId":"2c92c0f86179f24301619c0aecd727d3","tenantId":"23241","timezone":"America/Los_Angeles","displayName":"Minion Tenant 1"},{"id":"2c92c0f96178a7ae0161bde895c51cdf","name":"minion2","locale":"en_US","status":"Provisioned","entityId":"23355","parentId":"2c92c0f86179f24301619c0aecd727d3","tenantId":"23241","timezone":"America/Los_Angeles","displayName":"Minion Tenant 2"}]},"organizations":[],"options":[],"user_settings":{},"applications":[{"id":345,"name":"Billing Post Processor","status":"trial"}]}
    oauth_one_entity_with_3_login_redis = {}
    oauth_one_entity_with_3_login_redis["#{basic_one_entity_with_3_login['id']}::task_data"] = oauth_one_entity_with_3_login
    oauth_one_entity_with_3_login_redis["#{basic_one_entity_with_3_login['id']}::last_refresh"] = Time.now.to_i
    oauth_one_entity_with_3_login_redis["appInstance"] = oauth_one_entity_with_3_login['id']

    oauth_one_entity_with_3_login["target_login"]["login_entities"].pluck("id").each do |entity_id|
      oauth_one_entity_with_3_login_redis["#{oauth_one_entity_with_3_login['id']}::#{entity_id}::target_login::current_session"] = "find_a_way_to_put_in_unique_data_per_entity"           
      oauth_one_entity_with_3_login_redis["#{oauth_one_entity_with_3_login['id']}::#{entity_id}::target_login::bearer_token"] = "nsjjed-345td-2erds2-34"   
      oauth_one_entity_with_3_login_redis["#{oauth_one_entity_with_3_login['id']}::#{entity_id}::target_login::oauth_session_expires_at"] = Time.now.to_i + 1.hour
    end

    oauth_two_entity_with_3_login = {"id":1057773,"name":"sfffs","mode":"Collections","status":"Running","user":"Taylor Medford", "execution_timezone": "", "execution_interval": "", "target_login": { "tenant_type": "Zuora", "username": "tmedford_master@dchudy.sbx", "url": "https://apisandbox.zuora.com/apps/services/a/80.0", "status": "Active", "oauth_client_id": "4dbb232e-67b1-41b7-b0a7-6cc1732ff974", "oauth_secret": "QBpjg0Y53L59lsT=D2W8", "authentication_type": "OAUTH", "custom_data": {}, "entities": [ { "id": "2c92c0f86179f24301619c0aecd727d3", "name": "Global", "locale": "en_US", "status": "Provisioned", "entityId": "23241", "parentId": " ", "tenantId": "23241", "timezone": "America/Los_Angeles", "displayName": "Daniel Chudy Personal Sandbox" }, { "id": "2c92c0f861789e700161bde76f005327", "name": "Daniel Chudy Minion", "locale": "en_US", "status": "Provisioned", "entityId": "23356", "parentId": "2c92c0f86179f24301619c0aecd727d3", "tenantId": "23241", "timezone": "America/Los_Angeles", "displayName": "Minion Tenant 1" } ], "login_entities": [ { "id": "2c92c0f86179f24301619c0aecd727d3", "name": "Global", "locale": "en_US", "status": "Provisioned", "entityId": "23241", "parentId": " ", "tenantId": "23241", "timezone": "America/Los_Angeles", "displayName": "Daniel Chudy Personal Sandbox" }, { "id": "2c92c0f861789e700161bde76f005327", "name": "Daniel Chudy Minion", "locale": "en_US", "status": "Provisioned", "entityId": "23356", "parentId": "2c92c0f86179f24301619c0aecd727d3", "tenantId": "23241", "timezone": "America/Los_Angeles", "displayName": "Minion Tenant 1" }, { "id": "2c92c0f96178a7ae0161bde895c51cdf", "name": "minion2", "locale": "en_US", "status": "Provisioned", "entityId": "23355", "parentId": "2c92c0f86179f24301619c0aecd727d3", "tenantId": "23241", "timezone": "America/Los_Angeles", "displayName": "Minion Tenant 2" } ] }, "organizations": [], "options": [], "user_settings": { "timezone": "Eastern Time (US & Canada)", "local": "en", "id": 1 }, "applications": [ { "id": 345, "name": "Billing Post Processor", "status": "trial" }, { "id": 190, "name": "Workflow", "status": "trial" }, { "id": 447, "name": "Collections Manager - Collect", "status": "trial" } ] }
    oauth_two_entity_with_3_login_redis = {}
    oauth_two_entity_with_3_login_redis["#{basic_two_entity_with_3_login['id']}::task_data"] = basic_two_entity_with_3_login
    oauth_two_entity_with_3_login_redis["#{basic_two_entity_with_3_login['id']}::last_refresh"] = Time.now.to_i
    oauth_two_entity_with_3_login_redis["appInstance"] = oauth_two_entity_with_3_login['id']

    oauth_two_entity_with_3_login["target_login"]["login_entities"].pluck("id").each do |entity_id|
      oauth_two_entity_with_3_login_redis["#{oauth_two_entity_with_3_login['id']}::#{entity_id}::target_login::current_session"] = "AsdaweaSCADS"       
      oauth_two_entity_with_3_login_redis["#{oauth_two_entity_with_3_login['id']}::#{entity_id}::target_login::bearer_token"] "asbkdahjkcsasbeareberbeabbear"     
      oauth_two_entity_with_3_login_redis["#{oauth_two_entity_with_3_login['id']}::#{entity_id}::target_login::oauth_session_expires_at"] = Time.now.to_i + 1.hour
    end

    context 'Without Redis Cache' do 
      before do 
        @oauth_one_entity = connect_helper(task_info: oauth_one_entity)
        @oauth_one_entity_with_3_login = connect_helper(task_info: oauth_one_entity_with_3_login)
        @oauth_two_entity_with_3_login = connect_helper(task_info: oauth_two_entity_with_3_login) 
      end

      it 'check class type' do
        expect(@oauth_one_entity.target_login.client.class).to eq(ZuoraAPI::Oauth)
        expect(@oauth_one_entity_with_3_login.target_login.client.class).to eq(ZuoraAPI::Oauth)
        expect(@oauth_two_entity_with_3_login.target_login.client.class).to eq(ZuoraAPI::Oauth)
      end
    end 

    context 'With Redis Cache' do 
      before do 
        @oauth_one_entity = connect_helper(task_info: oauth_one_entity, task_redis_cache: oauth_one_entity_redis)
        @oauth_one_entity_with_3_login = connect_helper(task_info: oauth_one_entity_with_3_login,  task_redis_cache: oauth_one_entity_with_3_login_redis)
        @oauth_two_entity_with_3_login = connect_helper(task_info: oauth_two_entity_with_3_login,  task_redis_cache: oauth_two_entity_with_3_login_redis)
      end 

      it 'check class type' do
        expect(@oauth_one_entity.target_login.client.class).to eq(ZuoraAPI::Oauth)
        expect(@oauth_one_entity_with_3_login.target_login.client.class).to eq(ZuoraAPI::Oauth)
        expect(@oauth_two_entity_with_3_login.target_login.client.class).to eq(ZuoraAPI::Oauth)
      end
    end
  end 
  
  context 'Make Some Calls using the Connect Instances' do
  	before do
  		@client1 = @instance1.target_login.client
  		@client2 = @instance2.target_login.client
      @client3 = @instance3.target_login.client
  	end

  	it 'standard - success' do
        stub_request(:post, @client1.rest_endpoint('object/contact/2c92c0f95fbece47015fc66fda7042e3')).
          with(headers: {'Authorization'=>"Bearer c652cbc0ea384b9f81856a93a2a74538", 'Content-Type'=>'application/json; charset=utf-8'}).
          to_return(status: 200, body: '[{"id": "2c92c0f95fbece47015fc66fda7042e3","success": true}]')
        
        output_json, response  = @client1.rest_call(:method => :post, :session_type => :bearer, :url => @client1.rest_endpoint('object/contact/2c92c0f95fbece47015fc66fda7042e3'))

        expect(response.code).to eq(200)
  	end

  	it 'authentication_type Error' do
        expect {
          output_json, response  = @client2.rest_call(:method => :post, :session_type => :bearer, :url => @client2.rest_endpoint('object/contact/2c92c0f95fbece47015fc66fda7042e3'))
        }.to raise_error(ZuoraAPI::Exceptions::ZuoraAPIAuthenticationTypeError, "Basic Login, does not support Authentication of Type: bearer")
  	end

    it 'Entity Success' do
      stub_request(:post, @client3.rest_endpoint('object/contact/2c92c0f95fbece47015fc66fda7042e3')).
        with(headers: {'Authorization'=>"Bearer c652cbc0ea384b9f81856a93a2a74538", 'Content-Type'=>'application/json; charset=utf-8', 'entityId' =>'2c92c0f861789e700161bde76f005327'}).
        to_return(status: 200, body: '[{"id": "2c92c0f95fbece47015fc66fda7042e3","success": true}]')
      
      output_json, response  = @client3.rest_call(:method => :post, :session_type => :bearer, :url => @client3.rest_endpoint('object/contact/2c92c0f95fbece47015fc66fda7042e3'))    
      expect(response.code).to eq(200)
      expect(@client3.bearer_token).to eq("c652cbc0ea384b9f81856a93a2a74538")
      expect(@client3.oauth_client_id).to eq("4dbb232e-67b1-41b7-b0a7-6cc1732ff974")
    end

    it 'Complex Case' do
      stub_request(:post, @client1.rest_endpoint.chomp('v1/').concat('/events/event-triggers')).
        with(headers: {'Authorization'=>'Bearer c652cbc0ea384b9f81856a93a2a74538'}).
        to_return(status: 401, body: '{"message": "Authentication error"}')

      stub_request(:post, "https://rest.apisandbox.zuora.com/oauth/token").
        with(body: {"client_id"=>"#{@client1.oauth_client_id}", "client_secret"=>"#{@client1.oauth_secret}", "grant_type"=>"client_credentials"},
          headers: {'Content-Type'=>'application/x-www-form-urlencoded'}).
        to_return(status: 200, body: '{"access_token": "BOYA!!!!","token_type": "bearer","expires_in": 3599,"scope": "user.7c4d5433dc234c369a01b9719ecd059f entity.1a2b7a37-3e7d-4cb3-b0e2-883de9e766cc entity.c92ed977-510c-4c48-9b51-8d5e848671e9 service.echo.read tenant.19","jti": "c652cbc0ea384b9f81856a93a2a74539"}', headers: {})

      stub_request(:post, @client1.rest_endpoint.chomp('v1/').concat('/events/event-triggers')).
        with(headers: {'Authorization'=>'Bearer BOYA!!!!'}).
        to_return(status: 200, body: '{"message": "Success"}')

      @client1.rest_call(:method => :post, :url => @client1.rest_endpoint.chomp('v1/').concat('/events/event-triggers'), :session_type => :bearer)

      expect(@client1.current_session).to eq("HMtIQmN1TPC7IJymT_ovMyqrtB6o_KBf_zLQhkmTN20127SAEBQgDK_pPOc0geYgAZs_pm63EUsX41CO8OOEQEtRvGsfZPpuNLwVnuE0zYLN_yGNOrPdBGNNYyzoTlL3AL49UdcogjAms8_XJK7_tHdQN8C6P6S4u-2rgEz3DohxKec9Sv01Q8DCmH4X9MANh-Xs89uBnIcJlM2Ca4akGmJYaWV5q_CG8TK_3sbVuGN2_D7jR_7YyqLvFBAH3viX_CGW91UOjVlQ7UMQuNl-WIQ-q2g2wXGnR7hV7slXUank81c-e5a2hogmhoIIXz2FzH7uob2HkF13odvi6stAUhdR6tEPadJF2XfABvEdEfQ=")
      expect(@client1.bearer_token).to eq("BOYA!!!!")
      expect(@client1.oauth_expired?).to eq(false)    
    end
  end
end

def connect_helper(task_info: task_info, task_redis_cache: nil, connect_oauth_expired: false)

  #Initial call to connect to get new oauth
  if connect_oauth_expired
    instance = build(:appinstance, :expired)
    instance.id = task_info[:id] 

    token_response = {"access_token"=> instance["access_token"], "refresh_token" => instance["refresh_token"], "created_at" => 1478174449, "expires_in" => 2.hours.to_i}
    WebMock.stub_request(:post, "https://connect.zuora.com/oauth/token").
      with(body: "grant_type=refresh_token&redirect_uri=https%3A%2F%2Fconnect.zuora.com%2F&refresh_token=#{instance.refresh_token}").
      to_return( status: 200, body: token_response.to_json)
  else
    instance = build(:appinstance)
    instance.id = task_info[:id] 
  end
 
  #inject task redis cache so new session wont look for new task_data
  if task_redis_cache.present?
    Redis.current.set("AppInstance:#{task_info[:id]}", task_redis_cache.to_json)
  else
    stub_request(:get, "https://connect.zuora.com/api/v2/tools/tasks/#{instance.id}.json").
      with(body: "access_token=#{token_response['access_token']}").
      to_return( status: 200, body: task_info.to_json)
  end

  instance.new_session 

  #Check to make sure if expired oauth, that new tokens were set
  if connect_oauth_expired
    expect(instance.access_token).to eq(token_response['access_token'])
    expect(instance.refresh_token).to eq(token_response['refresh_token'])
    expect(instance.oauth_expires_at).to eq(Time.at(token_response["created_at"].to_i) + token_response["expires_in"].seconds)
  end

  #Check to make sure if no cache was present, that time to expire on task data is correct 
  if task_redis_cache.blank?
    #We made taks info call, so the last refresh should be less then time now
    expect(instance.last_refresh).to  be_between(Time.now.to_i - 10, Time.now.to_i)

    #Caching happens right after the task info call so we expect redis to be populated
    expect(Redis.current.get("AppInstance:#{task_info[:id]}").to eq(self.save_data.to_json)
    expect(Redis.current.ttl("AppInstance:#{task_info[:id]}").to be_between(Time.now.to_i - 10, Time.now.to_i)
  end
  
  return instance
end