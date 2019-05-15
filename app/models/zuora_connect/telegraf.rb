module ZuoraConnect
  class Telegraf
    attr_accessor :host

    OUTBOUND_METRICS = true      
    OUTBOUND_METRICS_NAME = "request-outbound"      
    INBOUND_METRICS = true      
    INBOUND_METRICS_NAME = "request-inbound"      

    def initialize 
      self.connect
    end

    def connect
      ZuoraConnect.logger.debug(self.format_metric_log('Telegraf','Need new connection')) if ZuoraConnect.configuration.telegraf_debug
      uri = URI.parse(ZuoraConnect.configuration.telegraf_endpoint)
      self.host = UDPSocket.new.tap do |socket|
        socket.connect uri.host, uri.port
      end
    rescue => ex
      self.host = nil
      ZuoraConnect.logger.warn(self.format_metric_log('Telegraf', "Failed to connect: #{ex.class}"))
    end

    def write(direction: 'Unknown', tags: {}, values: {})
      time = Benchmark.measure do |bench|
        # To avoid writing metrics from rspec tests
        if Rails.env.to_sym != :test
          app_instance = Thread.current[:appinstance].present? ? Thread.current[:appinstance].id : 0
          tags = { app_name: self.class.app_name, process_type: self.class.process_type, app_instance: app_instance, pod_name: self.class.pod_name}.merge(tags)

          if direction == :inbound
            if INBOUND_METRICS && !Thread.current[:inbound_metric].to_bool
              self.write_udp(series: INBOUND_METRICS_NAME, tags: tags, values: values) 
              Thread.current[:inbound_metric] = true
            else
              return
            end
          elsif direction == :outbound
            self.write_udp(series: OUTBOUND_METRICS_NAME, tags: tags, values: values) if OUTBOUND_METRICS
          else
            self.write_udp(series: direction, tags: tags, values: values)
          end
        end
      end
      if ZuoraConnect.configuration.telegraf_debug
        ZuoraConnect.logger.debug(self.format_metric_log('Telegraf', tags.to_s))
        ZuoraConnect.logger.debug(self.format_metric_log('Telegraf', values.to_s))
        ZuoraConnect.logger.debug(self.format_metric_log('Telegraf', "Writing '#{direction.capitalize}': #{time.real.round(5)} ms"))
      end
    end


    def write_udp(series: '', tags: {}, values: {})
      return if !values.present?
      self.host.write InfluxDB::PointValue.new({series: series, tags: tags, values: values}).dump 
    rescue => ex
      self.connect
      ZuoraConnect.logger.warn(self.format_metric_log('Telegraf',"Failed to write udp: #{ex.class}"))
    end

    def format_metric_log(message, dump = nil)
      message_color, dump_color = "1;91", "0;1"
      log_entry = "  \e[#{message_color}m#{message}\e[0m   "
      log_entry << "\e[#{dump_color}m%#{String === dump ? 's' : 'p'}\e[0m" % dump if dump
      if Rails.env == :development
        log_entry
      else
        [message, dump].compact.join(' - ')
      end
    end

    def self.app_name
      return ENV['DEIS_APP'].present? ? ENV['DEIS_APP'] : Rails.application.class.parent_name
    end

    def self.pod_name
      return ENV['HOSTNAME'].present? ? ENV['HOSTNAME'] :  Socket.gethostname
    end

    def self.full_process_name(process_name: nil, function: nil)
      keys = [self.pod_name, process_name.present? ? process_name : self.process_type, Process.pid, function]
      return keys.compact.join('][').prepend('[').concat(']')
    end

    # Returns the process type if any
    def self.process_type(default: 'Unknown')
      p_type = default
      if ENV['HOSTNAME'] && ENV['DEIS_APP']
        temp = ENV['HOSTNAME'].split(ENV['DEIS_APP'])[1]
        temp = temp.split(/(-[0-9a-zA-Z]{5})$/)[0] # remove the 5 char hash
        p_type = temp[1, temp.rindex("-")-1]
      end
      return p_type
    end
  end
end
