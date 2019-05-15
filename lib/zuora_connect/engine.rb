require 'rails/all'
require 'zuora_connect'
require 'apartment'
require 'httparty'
require 'zuora_api'

module ZuoraConnect
  class Engine < ::Rails::Engine
    isolate_namespace ZuoraConnect

    initializer "connect", before: :load_config_initializers do |app|
      Rails.application.routes.prepend do
        mount ZuoraConnect::Engine, at: "/connect"
        match '/api/connect/health', via: :all, to: 'zuora_connect/static#health'
        match '/api/connect/internal/data', via: :all, to: 'zuora_connect/static#metrics'       
      end
    end

    initializer :append_migrations do |app|
      unless app.root.to_s.match root.to_s
        config.paths["db/migrate"].expanded.each do |expanded_path|
          app.config.paths["db/migrate"] << expanded_path
        end
      end
    end

    initializer "connect.helpers" do
      ActiveSupport.on_load(:action_controller) do
        include ZuoraConnect::Controllers::Helpers
      end
    end
  end
end
