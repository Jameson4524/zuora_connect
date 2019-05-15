ZuoraConnect::Engine.routes.draw do
  get '/health' => 'static#health'
  get '/internal/data' => 'static#metrics'
  get '/invalid_session' => 'static#session_error', :as => :invalid_session
  get '/invalid_instance' => "static#invalid_app_instance_error", :as => :invalid_instance
  post '/initialize_app' => 'static#initialize_app'

  namespace :api do
    namespace :v1 do
      resources :app_instance, :only => [:index], defaults: {format: :json} do
          match "drop", via: [:get, :post], on: :collection
          match "cache_bust", via: [:get, :post], on: :collection
      end
    end
  end
end
