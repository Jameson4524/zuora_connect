require 'middleware/metrics_middleware'
require 'middleware/request_id_middleware'

module ZuoraConnect
  class Railtie < Rails::Railtie


    config.before_initialize do
      version = Rails.version
      if version >= "5.0.0"
        ::Rails.configuration.public_file_server.enabled = true
      elsif version >= "4.2.0"
        ::Rails.configuration.serve_static_files = true
      else
        ::Rails.configuration.serve_static_assets = true
      end
      ::Rails.configuration.action_dispatch.x_sendfile_header = nil
    end

    if defined? Prometheus
      initializer "prometheus.configure_rails_initialization" do |app|
        app.middleware.use Prometheus::Middleware::Exporter,(options ={:path => '/connect/internal/metrics'})
      end
    end
    initializer "zuora_connect.configure_rails_initialization" do |app|
      app.middleware.insert_after Rack::Sendfile, ZuoraConnect::MetricsMiddleware
      app.middleware.insert_after ActionDispatch::RequestId, ZuoraConnect::RequestIdMiddleware
    end

    # hook to process_action
    ActiveSupport::Notifications.subscribe('process_action.action_controller', ZuoraConnect::PageRequest.new)

    initializer(:rails_stdout_logging, before: :initialize_logger) do
      if Rails.env != 'development' && !ENV['DEIS_APP'].blank?
        require 'lograge'
  
        Rails.configuration.logger = ZuoraConnect.custom_logger(name: "Rails") 

        Rails.configuration.lograge.enabled = true
        Rails.configuration.colorize_logging = false
        if Rails.configuration.logger.class.to_s == 'Ougai::Logger'
          Rails.configuration.lograge.formatter = Class.new do |fmt|
            def fmt.call(data)
              { msg: 'Rails Request', request: data }
            end
          end
        end
        #Rails.configuration.lograge.formatter = Lograge::Formatters::Json.new
        Rails.configuration.lograge.custom_options = lambda do |event|
          exceptions = %w(controller action format id)
          items = {
            #time: event.time.strftime('%FT%T.%6N'),  
            params: event.payload[:params].except(*exceptions).to_json.to_s
          }
          items.merge!({exception_object: event.payload[:exception_object]}) if event.payload[:exception_object].present?
          items.merge!({exception: event.payload[:exception]}) if event.payload[:exception].present?

          if Thread.current[:appinstance].present? 
            items.merge!({appinstance_id: Thread.current[:appinstance].id, connect_user: Thread.current[:appinstance].connect_user, new_session: Thread.current[:appinstance].new_session_message})
            if Thread.current[:appinstance].logitems.present? && Thread.current[:appinstance].logitems.class == Hash
              items.merge!(Thread.current[:appinstance].logitems)
            end
          end
          return items        
        end
      end
    end
  end
end
