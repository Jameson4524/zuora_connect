module ZuoraConnect
  require 'uri'

  # Object of this class is passed to the ActiveSupport::Notification hook
  class PageRequest

    # This method is triggered when a non error page is loaded (not 404)
    def call(name, started, finished, unique_id, payload)
      # If the url contains any css or JavaScript files then do not collect metrics for them
      return nil if ["css", "assets", "jpg", "png", "jpeg", "ico"].any? { |word| payload[:path].include?(word) }

      # Getting the endpoint and the content_type
      content_hash = {:html => "text/html", :js => "application/javascript", :json => "application/json", :csv => "text/csv"}
      content_type = content_hash.key?(payload[:format]) ? content_hash[payload[:format]] : payload[:format]
      content_type = content_type.to_s.gsub('text/javascript', 'application/javascript')

      # payloads with 500 requests do not have status as it is not set by the controller
      # https://github.com/rails/rails/issues/33335
      #status_code = payload[:status] ? payload[:status] : payload[:exception_object].present? ? 500 : ""
      if payload[:exception].present? 
        status_code, exception = [500, payload[:exception].first]
      else
        status_code, exception = [payload[:status], nil]
      end

      tags = {method: payload[:method], status: status_code, error_type: exception, content_type: content_type, controller: payload[:controller], action: payload[:action]}.compact

      values = {view_time: payload[:view_runtime], db_time: payload[:db_runtime], response_time: ((finished-started)*1000)}.compact
      values = values.map{ |k,v| [k,v.round(2)]}.to_h

      ZuoraConnect::AppInstanceBase.write_to_telegraf(direction: :inbound, tags: tags, values: values)
    end
  end

  class MetricsMiddleware

    require "zuora_connect/version"
    require "zuora_api/version"

    def initialize(app)
      @app = app
    end

    def call(env)
      @bad_headers = ["HTTP_X_FORWARDED_FOR", "HTTP_X_FORWARDED_HOST", "HTTP_X_FORWARDED_PORT", "HTTP_X_FORWARDED_PROTO", "HTTP_X_FORWARDED_SCHEME", "HTTP_X_FORWARDED_SSL"] 
      if !ActionDispatch::Request::HTTP_METHODS.include?(env["REQUEST_METHOD"].upcase)
        [405, {"Content-Type" => "text/plain"}, ["Method Not Allowed"]]
      else
        if (env['HTTP_ZUORA_LAYOUT_FETCH_TEMPLATE_ID'].present?)
          Thread.current[:isHallway] = "/#{env['HTTP_ZUORA_LAYOUT_FETCH_TEMPLATE_ID']}"
          env['PATH_INFO'] = env['PATH_INFO'].gsub(Thread.current[:isHallway], '')
          env['REQUEST_URI'] = env['REQUEST_URI'].gsub(Thread.current[:isHallway], '')
          env['REQUEST_PATH'] = env['REQUEST_PATH'].gsub(Thread.current[:isHallway], '')

          #We need the forwarded host header to identify location of tenant
          whitelist = Regexp.new(".*[\.]zuora[\.]com$|^zuora[\.]com$")
          if whitelist.match(env['HTTP_X_FORWARDED_HOST']).present?
            @bad_headers.delete('HTTP_X_FORWARDED_HOST')
          end
        else
          Thread.current[:isHallway] = nil
        end

        #Remove bad headers
        @bad_headers.each { |header| env.delete(header) }

        #Thread.current[:appinstance] = nil
        start_time = Time.now
        begin
          @status, @headers, @response = @app.call(env)
        ensure 
          
          # If the url contains any CSS or JavaScript files then do not collect metrics for them
          if ["css", "assets", "jpg", "png", "jpeg", "ico"].any? { |word| env['PATH_INFO'].include?(word) } || /.*\.js$/.match(env['PATH_INFO'])
            tags = {status: @status, controller: 'ActionController', action: 'Assets', app_instance: 0}
            values = {response_time: ((Time.now - start_time)*1000).round(2) }
            ZuoraConnect::AppInstanceBase.write_to_telegraf(direction: 'request-inbound-assets', tags: tags, values: values)
          end

          if defined? Prometheus
            #Prometheus Stuff
            if env['PATH_INFO'] == '/connect/internal/metrics'

              #Do something before each scrape
              if defined? Resque.redis
                begin

                  Resque.redis.ping

                  Prometheus::REDIS_CONNECTION.set({connection:'redis',name: ZuoraConnect::Telegraf.app_name},1)
                  Prometheus::FINISHED_JOBS.set({type:'resque',name: ZuoraConnect::Telegraf.app_name},Resque.info[:processed])
                  Prometheus::PENDING_JOBS.set({type:'resque',name: ZuoraConnect::Telegraf.app_name},Resque.info[:pending])
                  Prometheus::ACTIVE_WORKERS.set({type:'resque',name: ZuoraConnect::Telegraf.app_name},Resque.info[:working])
                  Prometheus::WORKERS.set({type:'resque',name: ZuoraConnect::Telegraf.app_name},Resque.info[:workers])
                  Prometheus::FAILED_JOBS.set({type:'resque',name: ZuoraConnect::Telegraf.app_name},Resque.info[:failed])

                rescue Redis::CannotConnectError
                    Prometheus::REDIS_CONNECTION.set({connection:'redis',name: ZuoraConnect::Telegraf.app_name},0)
                end

                if ZuoraConnect.configuration.custom_prometheus_update_block != nil
                  ZuoraConnect.configuration.custom_prometheus_update_block.call()
                end
              end

            end
          end

          # Uncomment following block of code for handling engine requests/requests without controller
          # else
          #   # Handling requests which do not have controllers (engines)
          if env["SCRIPT_NAME"].present?
            controller_path = "#{env['SCRIPT_NAME'][1..-1]}"
            controller_path = controller_path.sub("/", "::")
            request_path = "#{controller_path}#UnknownAction"
          else
            # Writing to telegraf: Handle 404
            if [404, 500].include?(@status)
              content_type = @headers['Content-Type'].split(';')[0] if @headers['Content-Type']
              content_type = content_type.gsub('text/javascript', 'application/javascript')
              tags = {status: @status, content_type: content_type}
           
              tags = tags.merge({controller: 'ActionController'})
              tags = tags.merge({action: 'RoutingError' }) if @status == 404
              
              values = {response_time: ((Time.now - start_time)*1000).round(2) }

              ZuoraConnect::AppInstanceBase.write_to_telegraf(direction: :inbound, tags: tags, values: values)
            end
          end
          Thread.current[:inbound_metric] = nil
        end
        [@status, @headers, @response]
      end
    end
  end
end
