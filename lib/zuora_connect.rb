require 'zuora_connect/configuration'
require "zuora_connect/engine"
require 'zuora_connect/exceptions'
require 'zuora_connect/controllers/helpers'
require 'zuora_connect/views/helpers'
require 'zuora_connect/railtie'
require 'resque/additions'
require 'resque/dynamic_queues'
require 'resque/silence_done'
require 'resque/self_lookup'
require 'resque/plugins/custom_logger'
require 'logging/connect_formatter'
require 'metrics/influx/point_value'
require 'metrics/net'

module ZuoraConnect
  class << self
    attr_accessor :configuration
    attr_writer :logger

    def logger
      case Rails.env.to_s
      when 'development'
        Rails.logger
      else
        @logger ||= custom_logger(name: "Connect", level: Rails.logger.level)
      end
    end    

    def custom_logger(name: "", level: Rails.logger.present? ? Rails.logger.level : MonoLogger::INFO, type: :ougai)
      #puts name + ' - ' + {Logger::WARN => 'Logger::WARN', Logger::ERROR => 'Logger::ERROR', Logger::DEBUG => 'Logger::DEBUG', Logger::INFO => 'Logger::INFO' }[level] + ' - '
      if type == :ougai
        require 'ougai'
        #logger = Ougai::Logger.new(MonoLogger.new(STDOUT))
        logger = Ougai::Logger.new(STDOUT) 
        logger.formatter = Ougai::Formatters::ConnectFormatter.new(name)
        logger.level = level
        logger.before_log = lambda do |data|
          data[:trace_id] = ZuoraConnect::RequestIdMiddleware.request_id if ZuoraConnect::RequestIdMiddleware.request_id.present?
          data[:zuora_trace_id] = ZuoraConnect::RequestIdMiddleware.zuora_request_id if ZuoraConnect::RequestIdMiddleware.zuora_request_id.present?
          #data[:traces] = {amazon_id: data[:trace_id], zuora_id: data[:zuora_trace_id]}
          if !['ElasticAPM', 'ResqueScheduler', 'ResquePool', 'Resque', 'Makara'].include?(name) 
            if Thread.current[:appinstance].present?
              data[:app_instance_id] = Thread.current[:appinstance].id
              logitems = Thread.current[:appinstance].logitems
              if logitems.present? && logitems.class == Hash
                data[:tenant_ids] = logitems[:tenant_ids] if logitems[:tenant_ids].present?
                data[:organization] = logitems[:organization] if logitems[:organization].present?
              end
            end
          end
        end
      else
        logger = MonoLogger.new(STDOUT)
        logger.level = level
        logger.formatter =  proc do |serverity, datetime, progname, msg|
          begin
            msg = JSON.parse(msg)
          rescue JSON::ParserError => ex
          end

          require 'json'
          store = {
            name: name,
            level: serverity,
            timestamp: datetime.strftime('%FT%T.%6NZ'),
            pid: Process.pid,
            message: name == "ActionMailer" ? msg.strip : msg
          }
          if !['ElasticAPM', 'ResqueScheduler', 'ResquePool','Resque', 'Makara'].include?(name) 
            if Thread.current[:appinstance].present? 
              store[:app_instance_id] = Thread.current[:appinstance].id
              logitems = Thread.current[:appinstance].logitems
              if logitems.present? && logitems.class == Hash
                store[:tenant_ids] = logitems[:tenant_ids] if logitems[:tenant_ids].present?
                store[:organization] = logitems[:organization] if logitems[:organization].present?
              end
            end
          end
          JSON.dump(store) + "\n"
        end
      end
      return logger
    end      
  end

  module Controllers
    autoload :Helpers,        'zuora_connect/controllers/helpers'
  end

  module Views
    ActionView::Base.send(:include, Helpers)
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.reset
    @configuration = Configuration.new
  end

  def self.configure
    yield(configuration)
    ::Apartment.excluded_models << "Delayed::Job" if configuration.delayed_job
    ::Apartment.excluded_models.concat(configuration.additional_apartment_models) if configuration.additional_apartment_models.class == Array

    return configuration
  end

  def self.elastic_apm_defaults
    defaults = {}
    case Rails.env.to_s
    when 'production'
      defaults = {
        server_url: "http://apm-server.logging:8200",
        transaction_sample_rate: 0.20,
        capture_body: 'errors'
      }
    when 'staging'
      defaults = {
        server_url: "http://apm-server.logging:8200",
        transaction_sample_rate: 1.0
      }
    when 'development'
      defaults = {
        server_url: "http://logging.0.ecc.auw2.zuora:8200",
        transaction_sample_rate: 1.0
      }
    when 'test'
      defaults = {
        active: false, 
        disable_send: true
      }
    end

    defaults.merge!({
      disable_start_message: true,
      pool_size: 1, 
      transaction_max_spans: 500, 
      ignore_url_patterns: ['^\/admin\/resque.*', '^\/admin\/redis.*', '^\/admin\/peek.*', '^\/peek.*'], 
      verify_server_cert: false,
      log_level: Logger::INFO,
      service_name: ENV['DEIS_APP'].present? ? ENV['DEIS_APP'] : Rails.application.class.parent_name,
      logger: ZuoraConnect.custom_logger(name: "ElasticAPM", level: MonoLogger::WARN)
    })
    defaults.merge!({disable_send: true}) if defined?(Rails::Console)
    
    return defaults
  end
end
