if defined? Prometheus
  module Prometheus
    require "zuora_connect/version"
    require "zuora_api/version"

    # Create a default Prometheus registry for our metrics.
    prometheus = Prometheus::Client.registry

    # Create your metrics.
    ZUORA_VERSION = Prometheus::Client::Gauge.new(:zuora_version, 'The current Zuora Gem version.')
    CONNECT_VERSION = Prometheus::Client::Gauge.new(:gem_version, 'The current Connect Gem version.')
    RAILS_VERSION = Prometheus::Client::Gauge.new(:rails_version, 'The current Rails version.')
    RUBY_V = Prometheus::Client::Gauge.new(:ruby_version, 'The current Ruby version.')

    # Register your metrics with the registry we previously created.
    prometheus.register(ZUORA_VERSION);ZUORA_VERSION.set({version: ZuoraAPI::VERSION, name: ZuoraConnect::Telegraf.app_name},0)
    prometheus.register(CONNECT_VERSION);CONNECT_VERSION.set({version: ZuoraConnect::VERSION, name: ZuoraConnect::Telegraf.app_name},0)
    prometheus.register(RAILS_VERSION);RAILS_VERSION.set({version: Rails.version, name: ZuoraConnect::Telegraf.app_name},0)
    prometheus.register(RUBY_V);RUBY_V.set({version: RUBY_VERSION, name: ZuoraConnect::Telegraf.app_name},0)

    # Do they have resque jobs?
    if defined? Resque.redis
      REDIS_CONNECTION = Prometheus::Client::Gauge.new(:redis_connection, 'The status of the redis connection, 0 or 1')
      FINISHED_JOBS = Prometheus::Client::Gauge.new(:finished_jobs, 'Done resque jobs')
      WORKERS = Prometheus::Client::Gauge.new(:workers, 'Total resque workers')
      ACTIVE_WORKERS = Prometheus::Client::Gauge.new(:active_workers, 'Active resque workers')
      FAILED_JOBS = Prometheus::Client::Gauge.new(:failed_jobs, 'Failed resque jobs')
      PENDING_JOBS = Prometheus::Client::Gauge.new(:pending_jobs, 'Pending resque jobs')

      prometheus.register(REDIS_CONNECTION)
      prometheus.register(FINISHED_JOBS)
      prometheus.register(ACTIVE_WORKERS)
      prometheus.register(WORKERS)
      prometheus.register(FAILED_JOBS)
      prometheus.register(PENDING_JOBS)

    end

  end
end
