module ZuoraConnect
  require "uri"
  class AppInstanceBase < ActiveRecord::Base
    default_scope {select(ZuoraConnect::AppInstance.column_names.delete_if {|x| ["catalog_mapping", "catalog"].include?(x) }) }
    after_initialize :init
    after_create :initialize_redis_placeholder
    before_destroy :prune_data

    self.table_name = "zuora_connect_app_instances"
    attr_accessor :options, :mode, :logins, :task_data, :last_refresh, :username, :password, :s3_client, :api_version, :drop_message, :new_session_message, :connect_user, :logitems
    @@telegraf_host = nil
    REFRESH_TIMEOUT = 2.minute                #Used to determine how long to wait on current refresh call before executing another
    INSTANCE_REFRESH_WINDOW = 1.hours         #Used to set how how long till app starts attempting to refresh cached task connect data
    INSTANCE_REDIS_CACHE_PERIOD = 24.hours    #Used to determine how long to cached task data will live for
    API_LIMIT_TIMEOUT = 2.minutes             #Used to set the default for expiring timeout when api rate limiting is in effect
    BLANK_OBJECT_ID_LOOKUP = 'BlankValueSupplied'
    HOLDING_PATTERN_SLEEP = 5.seconds
    CONNECT_COMMUNICATION_SLEEP= 5.seconds
    IGNORED_LOCALS = ['fr', 'ja', 'sp']

    def init
      self.connect_user = 'Nobody'
      self.logitems = {}
      self.task_data = {}
      self.options = Hash.new
      self.logins = Hash.new
      self.api_version = "v2"
      self.attr_builder("timezone", ZuoraConnect.configuration.default_time_zone)
      self.attr_builder("locale", ZuoraConnect.configuration.default_locale)
      PaperTrail.whodunnit = "Backend" if defined?(PaperTrail)
      if defined?(ElasticAPM) && ElasticAPM.running?
        ElasticAPM.set_user("Backend")
        ElasticAPM.set_tag(:app_instance, self.id)
      end

      if INSTANCE_REFRESH_WINDOW > INSTANCE_REDIS_CACHE_PERIOD
        raise "The instance refresh window cannot be greater than the instance cache period"
      end
      self.apartment_switch(nil, false)
    end

    def initialize_redis_placeholder
      if defined?(Redis.current)
        Redis.current.zrem("AppInstance:Deleted", id)
        Redis.current.zadd("APILimits", 9999999999, "placeholder")
        Redis.current.zadd("InstanceRefreshing", 9999999999, "placeholder")
      end
      if defined?(Resque.redis)
        Resque.redis.zadd("PauseQueue", 9999999999, "placeholder")
      end
    end

    def prune_data(id: self.id)
      if defined?(Redis.current)
        Redis.current.zadd("AppInstance:Deleted", Time.now.to_i, id)
        Redis.current.del("AppInstance:#{id}")
        Redis.current.zrem("APILimits", id)
        Redis.current.zrem("InstanceRefreshing", id)
      end
      if defined?(Resque.redis)
        Resque.redis.zrem("PauseQueue", id)
      end
      return true
    end

    def apartment_switch(method = nil, migrate = false)
      switch_count ||= 0
      if self.persisted?
        begin
          Apartment::Tenant.switch!(self.id)
        rescue Apartment::TenantNotFound => ex
          sleep(2)
          begin
            Apartment::Tenant.create(self.id.to_s)
          rescue Apartment::TenantExists => ex
          end
          if (switch_count += 1) < 2
            retry
          else
            raise
          end
        end
        if migrate && ActiveRecord::Migrator.needs_migration?
          Apartment::Migrator.migrate(self.id)
        end
      end
      Thread.current[:appinstance] = self
    end

    def new_session(session: self.data_lookup, username: self.access_token, password: self.refresh_token, holding_pattern: false, log_level: Logger::DEBUG)
      self.api_version = "v2"
      self.username = username
      self.password = password
      self.last_refresh = session["#{self.id}::last_refresh"]
      self.connect_user = session["#{self.id}::user::email"] if session["#{self.id}::user::email"].present?
      PaperTrail.whodunnit = self.connect_user if defined?(PaperTrail)
      ElasticAPM.set_user(self.connect_user)   if defined?(ElasticAPM) && ElasticAPM.running?
      recoverable_session = false

      ## DEV MODE TASK DATA MOCKUP
      if ZuoraConnect.configuration.mode != "Production"
        mock_task_data = {
          "mode" => ZuoraConnect.configuration.dev_mode_mode
        }

        case ZuoraConnect.configuration.dev_mode_options.class
        when Hash
          self.options = ZuoraConnect.configuration.dev_mode_options
        when Array
          mock_task_data["options"] = ZuoraConnect.configuration.dev_mode_options
        end

        ZuoraConnect.configuration.dev_mode_logins.each do |k,v|
          v = v.merge({"entities": [] }) if !v.keys.include?("entities")
          mock_task_data[k] = v
        end

        self.build_task(task_data: mock_task_data, session: session)
      else
        time_expire = (session["#{self.id}::last_refresh"] || Time.now).to_i - INSTANCE_REFRESH_WINDOW.ago.to_i

        if session.empty?
          self.new_session_message = "REFRESHING - Session Empty"
          ZuoraConnect.logger.add(log_level, self.new_session_message)
          raise ZuoraConnect::Exceptions::HoldingPattern if holding_pattern && !self.mark_for_refresh
          self.refresh(session: session)

        elsif (self.id != session["appInstance"].to_i)
          self.new_session_message = "REFRESHING - AppInstance ID(#{self.id}) does not match session id(#{session["appInstance"].to_i})"
          ZuoraConnect.logger.add(log_level, self.new_session_message)
          raise ZuoraConnect::Exceptions::HoldingPattern if holding_pattern && !self.mark_for_refresh
          self.refresh(session: session)

        elsif session["#{self.id}::task_data"].blank?
          self.new_session_message = "REFRESHING - Task Data Blank"
          ZuoraConnect.logger.add(log_level, self.new_session_message)
          raise ZuoraConnect::Exceptions::HoldingPattern if holding_pattern && !self.mark_for_refresh
          self.refresh(session: session)

        elsif session["#{self.id}::last_refresh"].blank?
          self.new_session_message = "REFRESHING - No Time on Cookie"
          recoverable_session = true
          ZuoraConnect.logger.add(log_level, self.new_session_message)
          raise ZuoraConnect::Exceptions::HoldingPattern if holding_pattern && !self.mark_for_refresh
          self.refresh(session: session)

        # If the cache is expired and we can aquire a refresh lock
        elsif (session["#{self.id}::last_refresh"].to_i < INSTANCE_REFRESH_WINDOW.ago.to_i) && self.mark_for_refresh
          self.new_session_message = "REFRESHING - Session Old by #{time_expire.abs} second"
          recoverable_session = true
          ZuoraConnect.logger.add(log_level, self.new_session_message)
          self.refresh(session: session)

        else
          if time_expire < 0
            self.new_session_message = ["REBUILDING - Expired by #{time_expire} seconds", self.marked_for_refresh? ? " cache updating as of #{self.reset_mark_refreshed_at} seconds ago" : nil].compact.join(',')
          else
            self.new_session_message = "REBUILDING - Expires in #{time_expire} seconds"
          end
          ZuoraConnect.logger.add(log_level, self.new_session_message)
          self.build_task(task_data: session["#{self.id}::task_data"], session: session)
        end
      end
      return self
    rescue ZuoraConnect::Exceptions::HoldingPattern => ex
      while self.marked_for_refresh?
        ZuoraConnect.logger.info("Holding - Expires in #{self.reset_mark_expires_at}. '#{self.new_session_message}'")
        sleep(HOLDING_PATTERN_SLEEP)
      end
      self.reload_attributes([:refresh_token, :oauth_expires_at, :access_token])
      session = self.data_lookup(session: session)
      retry
    rescue => ex
      if recoverable_session
        ZuoraConnect.logger.warn("REBUILDING - Using backup expired cache")
        self.build_task(task_data: session["#{self.id}::task_data"], session: session)
        return self
      else
        raise
      end
    ensure
      begin
        I18n.locale = self.locale
      rescue I18n::InvalidLocale => ex
        ZuoraConnect.logger.error(ex) if !IGNORED_LOCALS.include?(ex.locale.to_s.downcase)
      end
      Time.zone = self.timezone
      tenants = self.task_data.dig('tenant_ids') || []
      organizations = self.task_data.dig('organizations') || []
      if defined?(ElasticAPM) && ElasticAPM.running?
        ElasticAPM.set_tag(:tenant_id, tenants.first) 
        ElasticAPM.set_tag(:organization, organizations.first) 
      end
      self.logitem(item: {tenant_ids: tenants, organization: organizations})
      self.update_column(:name, self.task_data.dig('name')) if ZuoraConnect::AppInstance.column_names.include?('name') && self.task_data.dig('name') != self.name
    end

    def refresh(session: {}, session_fallback: false)
      refresh_count ||= 0
      start = Time.now
      response = HTTParty.get(ZuoraConnect.configuration.url + "/api/#{self.api_version}/tools/tasks/#{self.id}.json",:body => {:access_token => self.access_token})
      response_time = Time.now - start

      ZuoraConnect.logger.debug("[#{self.id}] REFRESH TASK - Connect Task Info Request Time #{response_time.round(2).to_s}")
      if response.code == 200
        self.build_task(task_data: JSON.parse(response.body), session: session)
        self.last_refresh = Time.now.to_i
        self.cache_app_instance
        self.reset_mark_for_refresh
      else
        raise ZuoraConnect::Exceptions::ConnectCommunicationError.new("Error Communicating with Connect", response.body, response.code)
      end
    rescue *(ZuoraAPI::Login::CONNECTION_EXCEPTIONS).concat(ZuoraAPI::Login::CONNECTION_READ_EXCEPTIONS) => ex
      if (refresh_count += 1) < 3
        ZuoraConnect.logger.info("[#{self.id}] REFRESH TASK - #{ex.class} Retrying(#{refresh_count})")
        retry
      else
        ZuoraConnect.logger.fatal("[#{self.id}] REFRESH TASK - #{ex.class} Failed #{refresh_count}x")
        raise
      end
    rescue ZuoraConnect::Exceptions::ConnectCommunicationError => ex
      if (refresh_count += 1) < 3
        if ex.code == 401
          ZuoraConnect.logger.info("[#{self.id}] REFRESH TASK - Failed #{ex.code} - Retrying(#{refresh_count})")
          self.refresh_oauth
        else
          ZuoraConnect.logger.warn("[#{self.id}] REFRESH TASK - Failed #{ex.code} - Retrying(#{refresh_count})")
        end
        retry
      else
        ZuoraConnect.logger.fatal("[#{self.id}] REFRESH TASK - Failed #{ex.code} - #{refresh_count}x")
        raise
      end
    end

    #### START Metrics Mathods ####
      def logitem(item: {}, reset: false)
        self.logitems = {} if self.logitems.class != Hash
        if item.class == Hash
          self.logitems = reset ? item : self.logitems.merge(item)
        end
        Thread.current[:appinstance] = self
      end

      def self.write_to_telegraf(*args)
        if ZuoraConnect.configuration.enable_metrics
          @@telegraf_host = ZuoraConnect::Telegraf.new() if @@telegraf_host == nil
          unicorn_stats = self.unicorn_listener_stats() if defined?(Unicorn) && Unicorn.respond_to?(:listener_names)
          @@telegraf_host.write(direction: 'Raindrops', tags: {}, values: unicorn_stats)  unless unicorn_stats.blank?
          return @@telegraf_host.write(*args)
        end
      end

      def self.unicorn_listener_stats ()
        stats_hash = {}
        stats_hash["total_active"] = 0
        stats_hash["total_queued"] = 0

        begin 
          tmp = Unicorn.listener_names
          unix = tmp.grep(%r{\A/})
          tcp = tmp.grep(/\A.+:\d+\z/)
          tcp = nil if tcp.empty?
          unix = nil if unix.empty?


          Raindrops::Linux.tcp_listener_stats(tcp).each do |addr,stats|
            stats_hash["active_#{addr}"] = stats.active
            stats_hash["queued_#{addr}"] = stats.queued
            stats_hash["total_active"] = stats.active + stats_hash["total_active"]
            stats_hash["total_queued"] = stats.queued + stats_hash["total_queued"]
          end if tcp

          Raindrops::Linux.unix_listener_stats(unix).each do |addr,stats|
            stats_hash["active_#{addr}"] = stats.active
            stats_hash["queued_#{addr}"] = stats.queued
            stats_hash["total_active"] = stats.active + stats_hash["total_active"]
            stats_hash["total_queued"] = stats.queued + stats_hash["total_queued"]
          end if unix
        rescue IOError => ex
        rescue => ex
          ZuoraConnect.logger.error(ex)
        end
        return stats_hash
      end

      def self.get_metrics(type)
        @data = {}

        if type == "versions"
          @data = {
            app_name: ZuoraConnect::Telegraf.app_name,
            url: "dummy",
            Version_Gem: ZuoraConnect::VERSION,
            Version_Zuora: ZuoraAPI::VERSION ,
            Version_Ruby: RUBY_VERSION,
            Version_Rails: Rails.version,
            hold: 1
          }
        elsif type == "stats"
          begin
            Resque.redis.ping
            @resque = Resque.info
            @data = {
              app_name: ZuoraConnect::Telegraf.app_name,
              url: "dummy",
              Resque:{
                Jobs_Finished: @resque[:processed] ,
                Jobs_Failed: @resque[:failed],
                Jobs_Pending: @resque[:pending],
                Workers_Active: @resque[:working],
                Workers_Total: @resque[:workers]
              }
            }
          rescue
          end
        end
        return @data
      end
    #### END Task Mathods ####

    #### START Task Mathods ####
      def build_task(task_data: {}, session: {})
        session = {} if session.blank?
        self.task_data = task_data
        self.mode = self.task_data["mode"]
        self.task_data.each do |k,v|
          if k.match(/^(.*)_login$/)
            tmp = ZuoraConnect::Login.new(v)
            if v["tenant_type"] == "Zuora"
              if tmp.entities.size > 0
                tmp.entities.each do |value|
                  entity_id = value["id"]
                  tmp.client(entity_id).current_session          = session["#{self.id}::#{k}::#{entity_id}:current_session"]               if session["#{self.id}::#{k}::#{entity_id}:current_session"]
                  tmp.client(entity_id).bearer_token             = session["#{self.id}::#{k}::#{entity_id}:bearer_token"]                  if session["#{self.id}::#{k}::#{entity_id}:bearer_token"]
                  tmp.client(entity_id).oauth_session_expires_at = session["#{self.id}::#{k}::#{entity_id}:oauth_session_expires_at"]      if session["#{self.id}::#{k}::#{entity_id}:oauth_session_expires_at"]
                end
              else
                tmp.client.current_session                       = session["#{self.id}::#{k}:current_session"]                             if session["#{self.id}::#{k}:current_session"]
                tmp.client.bearer_token                          = session["#{self.id}::#{k}:bearer_token"]                                if session["#{self.id}::#{k}:bearer_token"] && tmp.client.respond_to?(:bearer_token) ## need incase session id goes from basic to aouth in same redis store
                tmp.client.oauth_session_expires_at              = session["#{self.id}::#{k}:oauth_session_expires_at"]                    if session["#{self.id}::#{k}:oauth_session_expires_at"]  && tmp.client.respond_to?(:oauth_session_expires_at)
              end
            end
            self.logins[k] = tmp
            self.attr_builder(k, @logins[k])
          elsif k == "options"
            v.each do |opt|
              self.options[opt["config_name"]] = opt
            end
          elsif k == "user_settings"
            self.timezone =  v["timezone"]
            self.locale = v["local"]
          end
        end
      rescue => ex
        ZuoraConnect.logger.error("Task Data: #{task_data}") if task_data.present?
        if session.present?
          ZuoraConnect.logger.error("Task Session: #{session.to_h}")  if session.methods.include?(:to_h)
          ZuoraConnect.logger.error("Task Session: #{session.to_hash}") if session.methods.include?(:to_hash)
        end
        raise
      end

      def updateOption(optionId, value)
        response = HTTParty.get(ZuoraConnect.configuration.url + "/api/#{self.api_version}/tools/application_options/#{optionId}/edit?value=#{value}",:body => {:access_token => self.username})
      end

      #This can update an existing login, add a new login, change to another existing login
      #EXAMPLE: {"name": "ftp_login_14","username": "ftplogin7","tenant_type": "Custom","password": "test2","url": "www.ftp.com","custom_data": {  "path": "/var/usr/test"}}
      def update_logins(options)
        update_login_count ||= 0
        response = HTTParty.post(ZuoraConnect.configuration.url + "/api/#{self.api_version}/tools/tasks/#{self.id}/logins",:body => {:access_token => self.username}.merge(options))
        parsed_json =  JSON.parse(response.body)
        if response.code == 200
          if defined?(Redis.current)
            self.build_task(task_data: parsed_json, session: self.data_lookup)
            self.last_refresh = Time.now.to_i
            self.cache_app_instance
          end
          return parsed_json
        elsif response.code == 400
          raise ZuoraConnect::Exceptions::APIError.new(message: parsed_json['errors'].join(' '), response: response.body, code: response.code)
        else
          raise ZuoraConnect::Exceptions::ConnectCommunicationError.new("Error Communicating with Connect", response.body, response.code)
        end
      rescue *(ZuoraAPI::Login::CONNECTION_EXCEPTIONS).concat(ZuoraAPI::Login::CONNECTION_READ_EXCEPTIONS) => ex
        if (update_login_count += 1) < 3
          retry
        else
          raise
        end
      rescue ZuoraConnect::Exceptions::ConnectCommunicationError => ex
        if (update_login_count += 1) < 3
          if ex.code == 401
            self.refresh_oauth
          end
          retry
        else
          raise
        end
      end

      def update_task(options)
        update_task_count ||= 0
        response = HTTParty.post(ZuoraConnect.configuration.url + "/api/#{self.api_version}/tools/tasks/#{self.id}/update_task",:body => {:access_token => self.username}.merge(options))
        parsed_json =  JSON.parse(response.body)
        if response.code == 200
          return parsed_json
        elsif response.code == 400
          raise ZuoraConnect::Exceptions::APIError.new(message: parsed_json['errors'].join(' '), response: response.body, code: response.code)
        else
          raise ZuoraConnect::Exceptions::ConnectCommunicationError.new("Error Communicating with Connect", response.body, response.code)
        end
      rescue *(ZuoraAPI::Login::CONNECTION_EXCEPTIONS).concat(ZuoraAPI::Login::CONNECTION_READ_EXCEPTIONS) => ex
        if (update_task_count += 1) < 3
          retry
        else
          raise
        end
      rescue ZuoraConnect::Exceptions::ConnectCommunicationError => ex
        if (update_task_count += 1) < 3
          if ex.code == 401
            self.refresh_oauth
          end
          retry
        else
          raise
        end
      end
    #### END Task Mathods ####

    #### START Connect OAUTH methods ####
      def check_oauth_state(method)
        #Refresh token if already expired
        if self.oauth_expired?
          ZuoraConnect.logger.debug("[#{self.id}] Before '#{method}' method, Oauth expired")
          self.refresh_oauth
        end
      end

      def oauth_expired?
        return self.oauth_expires_at.present? ? (self.oauth_expires_at < Time.now.utc) : true
      end

      def refresh_oauth
        refresh_oauth_count ||= 0
        start = Time.now
        params = {
                  :grant_type => "refresh_token",
                  :redirect_uri => ZuoraConnect.configuration.oauth_client_redirect_uri,
                  :refresh_token => self.refresh_token
                }
        response = HTTParty.post("#{ZuoraConnect.configuration.url}/oauth/token",:body => params)
        response_time = Time.now - start
        ZuoraConnect.logger.debug("[#{self.id}] REFRESH OAUTH - In #{response_time.round(2).to_s}")

        if response.code == 200
          response_body = JSON.parse(response.body)

          self.refresh_token = response_body["refresh_token"]
          self.access_token = response_body["access_token"]
          self.oauth_expires_at = Time.at(response_body["created_at"].to_i) + response_body["expires_in"].seconds
          self.save(:validate => false)
        else
          raise ZuoraConnect::Exceptions::ConnectCommunicationError.new("Error Refreshing Access Token for #{self.id}", response.body, response.code)
        end
      rescue *(ZuoraAPI::Login::CONNECTION_EXCEPTIONS).concat(ZuoraAPI::Login::CONNECTION_READ_EXCEPTIONS) => ex
        if (refresh_oauth_count += 1) < 3
          ZuoraConnect.logger.info("[#{self.id}] REFRESH OAUTH - #{ex.class} Retrying(#{refresh_oauth_count})")
          retry
        else
          ZuoraConnect.logger.fatal("[#{self.id}] REFRESH OAUTH - #{ex.class} Failed #{refresh_oauth_count}x")
          raise
        end
      rescue ZuoraConnect::Exceptions::ConnectCommunicationError => ex
        sleep(CONNECT_COMMUNICATION_SLEEP)
        self.reload_attributes([:refresh_token, :oauth_expires_at, :access_token]) #Reload only the refresh token for retry

        #After reload, if nolonger expired return
        return if !self.oauth_expired?

        if (refresh_oauth_count += 1) < 3
          ZuoraConnect.logger.info("[#{self.id}] REFRESH OAUTH - Failed #{ex.code} - Retrying(#{refresh_oauth_count})")
          retry
        else
          ZuoraConnect.logger.fatal("[#{self.id}] REFRESH OAUTH - Failed #{ex.code} - #{refresh_oauth_count}x")
          raise
        end
      end
    #### END Connect OAUTH methods ####

    #### START AppInstance Temporary Persistance Methods ####
      def marked_for_refresh?
        if defined?(Redis.current)
          Redis.current.zremrangebyscore("InstanceRefreshing", "0", "(#{Time.now.to_i}")
          return Redis.current.zscore("InstanceRefreshing", self.id).present?
        else
          return false
        end
      end

      def reset_mark_for_refresh
        Redis.current.zrem("InstanceRefreshing", self.id) if defined?(Redis.current)
      end

      def reset_mark_refreshed_at
        return defined?(Redis.current) ? REFRESH_TIMEOUT.to_i - reset_mark_expires_at : 0
      end

      def reset_mark_expires_at
        if defined?(Redis.current)
          refresh_time = Redis.current.zscore("InstanceRefreshing", self.id)
          return refresh_time.present? ? (refresh_time - Time.now.to_i).round(0) : 0
        else
          return 0
        end
      end

      def mark_for_refresh
        return defined?(Redis.current) ? Redis.current.zadd("InstanceRefreshing", Time.now.to_i + REFRESH_TIMEOUT.to_i, self.id, {:nx => true}) : true
      end

      def data_lookup(session: {})
        if defined?(Redis.current)
          begin
            redis_get_command ||= 0
            cached_instance = Redis.current.get("AppInstance:#{self.id}")
          rescue *(ZuoraAPI::Login::CONNECTION_EXCEPTIONS).concat(ZuoraAPI::Login::CONNECTION_READ_EXCEPTIONS) => ex
            if (redis_get_command += 1) < 3
              retry
            else
              raise
            end
          end
          if cached_instance.blank?
            ZuoraConnect.logger.debug("[#{self.id}] Cached AppInstance Missing")
            return session
          else
            ZuoraConnect.logger.debug("[#{self.id}] Cached AppInstance Found")
            return decrypt_data(data: cached_instance, rescue_return: session).merge(session)
          end
        else
          return session
        end
      end

      def cache_app_instance
        if defined?(Redis.current)
          #Task data must be present and the last refresh cannot be old. We dont want to overwite new cache data with old
          if self.task_data.present? &&  (self.last_refresh.to_i > INSTANCE_REFRESH_WINDOW.ago.to_i)
            ZuoraConnect.logger.debug("[#{self.id}] Caching AppInstance")
            Redis.current.setex("AppInstance:#{self.id}", INSTANCE_REDIS_CACHE_PERIOD.to_i, self.encrypt_data(data: self.save_data))
          end
        end
      end

      def save_data(session = Hash.new)
        self.logins.each do |key, login|
          if login.tenant_type == "Zuora"
            if login.available_entities.size > 1 && Rails.application.config.session_store != ActionDispatch::Session::CookieStore
              login.available_entities.each do |entity_key|
                session["#{self.id}::#{key}::#{entity_key}:current_session"]            = login.client(entity_key).current_session            if login.client.respond_to?(:current_session)
                session["#{self.id}::#{key}::#{entity_key}:bearer_token"]               = login.client(entity_key).bearer_token               if login.client.respond_to?(:bearer_token)
                session["#{self.id}::#{key}::#{entity_key}:oauth_session_expires_at"]   = login.client(entity_key).oauth_session_expires_at   if login.client.respond_to?(:oauth_session_expires_at)
              end
            else
              session["#{self.id}::#{key}:current_session"]             = login.client.current_session            if login.client.respond_to?(:current_session)
              session["#{self.id}::#{key}:bearer_token"]                = login.client.bearer_token               if login.client.respond_to?(:bearer_token)
              session["#{self.id}::#{key}:oauth_session_expires_at"]    = login.client.oauth_session_expires_at   if login.client.respond_to?(:oauth_session_expires_at)
            end
          end
        end

        session["#{self.id}::task_data"] = self.task_data

        #Redis is not defined strip out old data
        if !defined?(Redis.current)
          session["#{self.id}::task_data"].delete('applications')
          session["#{self.id}::task_data"].delete('tenant_ids')
          session["#{self.id}::task_data"].delete('organizations')
          session["#{self.id}::task_data"].select {|k,v| k.include?('login') && v['tenant_type'] == 'Zuora'}.each do |login_key, login_data|
            session["#{self.id}::task_data"][login_key]['entities'] = (login_data.dig('entities') || []).map {|entity| entity.slice('id', 'tenantId')}
          end
        end

        session["#{self.id}::last_refresh"] = self.last_refresh
        session["appInstance"] = self.id
        return session
      end

      def encryptor
        # Default values for Rails 4 apps
        key_iter_num, key_size, salt, signed_salt = [1000, 64, "encrypted cookie", "signed encrypted cookie"]
        raise ZuoraConnect::Exceptions::Error.new("'secret_key_base' is not set for rails environment '#{Rails.env}'. Please set in secrets file.") if Rails.application.secrets.secret_key_base.blank?
        key_generator = ActiveSupport::KeyGenerator.new(Rails.application.secrets.secret_key_base, iterations: key_iter_num)
        secret, sign_secret = [key_generator.generate_key(salt, 32), key_generator.generate_key(signed_salt)]
        return ActiveSupport::MessageEncryptor.new(secret, sign_secret)
      end

      def decrypt_data(data: nil, rescue_return: nil, log_fatal: true)
        return data if data.blank?
        if Rails.env == 'development'
          begin
            return JSON.parse(data)
          rescue JSON::ParserError => ex
            return data
          end
        else
          begin
            return JSON.parse(encryptor.decrypt_and_verify(CGI::unescape(data)))
          rescue ActiveSupport::MessageVerifier::InvalidSignature => ex
            ZuoraConnect.logger.add(Logger::ERROR, "Error Decrypting for #{self.id}") if log_fatal
            return rescue_return
          rescue JSON::ParserError => ex
            return encryptor.decrypt_and_verify(CGI::unescape(data))
          end
        end
      end

      def encrypt_data(data: nil)
        return data if data.blank?
        if Rails.env == 'development'
          return data.to_json
        else
          return encryptor.encrypt_and_sign(data.to_json)
        end
      end
    #### END AppInstance Temporary Persistance Methods ####

    ### START Resque Helping Methods ####
      def api_limit(start: true, time: API_LIMIT_TIMEOUT.to_i)
        if start
          Redis.current.zadd("APILimits", Time.now.to_i + time, self.id)
        else
          Redis.current.zrem("APILimits", self.id)
        end
      end

      def api_limit?
        Redis.current.zremrangebyscore("APILimits", "0", "(#{Time.now.to_i}")
        return Redis.current.zscore("APILimits", self.id).present?
      end

      def queue_paused?
        Resque.redis.zremrangebyscore("PauseQueue", "0", "(#{Time.now.to_i}")
        return Resque.redis.zrange("PauseQueue", 0, -1).map {|key| key.split("__")[0]}.include?(self.id.to_s)
      end

      def queue_pause(time: nil, current_user: 'Default')
        key = "#{self.id}__#{current_user}"
        if time.present?
          raise "Time must be integer of seconds instead of #{time.class}." if !['Integer', 'Fixnum'].include?(time.class.to_s)
          Resque.redis.zadd("PauseQueue", Time.now.to_i + time, key)
        else
          Resque.redis.zadd("PauseQueue", 9999999999, key)
        end
      end

      def queue_start(current_user: 'Default')
        paused_user = Resque.redis.zrange("PauseQueue", 0, -1).map {|key| key.split("__")[0] == "#{self.id}" ? key.split("__")[1] : nil}.compact.first
        if paused_user == current_user || paused_user.blank?
          Resque.redis.zrem("PauseQueue", "#{self.id}__#{paused_user}")
        else
          raise "Can only unpause for user #{paused_user}."
        end
      end
    ### END Resque Helping Methods ####

    ### START Catalog Helping Methods #####
      def get_catalog(page_size: 5, zuora_login: self.login_lookup(type: "Zuora").first, entity_id: nil)
        self.update_column(:catalog_update_attempt_at, Time.now.utc)

        entity_reference = entity_id.blank? ? 'Default' : entity_id
        ZuoraConnect.logger.debug("Fetch Catalog")
        ZuoraConnect.logger.debug("Zuora Entity: #{entity_id.blank? ? 'default' : entity_id}")

        login = zuora_login.client(entity_reference)

        old_logger = ActiveRecord::Base.logger
        ActiveRecord::Base.logger = nil
        ActiveRecord::Base.connection.execute('UPDATE "public"."zuora_connect_app_instances" SET "catalog" = jsonb_set("catalog", \'{tmp}\', \'{}\'), "catalog_mapping" = jsonb_set("catalog_mapping", \'{tmp}\', \'{}\') where "id" = %{id}' % {:id => self.id})

        response = {'nextPage' => login.rest_endpoint("catalog/products?pageSize=#{page_size}")}
        while !response["nextPage"].blank?
          url = login.rest_endpoint(response["nextPage"].split('/v1/').last)
          ZuoraConnect.logger.debug("Fetch Catalog URL #{url}")
          output_json, response = login.rest_call(:debug => false, :url => url, :errors => [ZuoraAPI::Exceptions::ZuoraAPISessionError], :timeout_retry => true)
          ZuoraConnect.logger.debug("Fetch Catalog Response Code #{response.code}")

          if !output_json['success'] =~ (/(true|t|yes|y|1)$/i) || output_json['success'].class != TrueClass
            ZuoraConnect.logger.error("Fetch Catalog DATA #{output_json.to_json}")
            raise ZuoraAPI::Exceptions::ZuoraAPIError.new("Error Getting Catalog: #{output_json}")
          end

          output_json["products"].each do |product|
            ActiveRecord::Base.connection.execute('UPDATE "public"."zuora_connect_app_instances" SET "catalog_mapping" = jsonb_set("catalog_mapping", \'{tmp, %s}\', \'%s\') where "id" = %s' % [product["id"], {"productId" => product["id"]}.to_json.gsub("'", "''"), self.id])
            rateplans = {}

            product["productRatePlans"].each do |rateplan|
              ActiveRecord::Base.connection.execute('UPDATE "public"."zuora_connect_app_instances" SET "catalog_mapping" = jsonb_set("catalog_mapping", \'{tmp, %s}\', \'%s\') where "id" = %s' % [rateplan["id"],  {"productId" => product["id"], "productRatePlanId" => rateplan["id"]}.to_json.gsub("'", "''"), self.id])
              charges = {}

              rateplan["productRatePlanCharges"].each do |charge|
                ActiveRecord::Base.connection.execute('UPDATE "public"."zuora_connect_app_instances" SET "catalog_mapping" = jsonb_set("catalog_mapping", \'{tmp, %s}\', \'%s\') where "id" = %s' % [charge["id"],  {"productId" => product["id"], "productRatePlanId" => rateplan["id"], "productRatePlanChargeId" => charge["id"]}.to_json.gsub("'", "''"), self.id])

                charges[charge["id"]] = charge.merge({"productId" => product["id"], "productName" => product["name"], "productRatePlanId" => rateplan["id"], "productRatePlanName" => rateplan["name"] })
              end

              rateplan["productRatePlanCharges"] = charges
              rateplans[rateplan["id"]] = rateplan.merge({"productId" => product["id"], "productName" => product["name"]})
            end
            product["productRatePlans"] = rateplans

            ActiveRecord::Base.connection.execute('UPDATE "public"."zuora_connect_app_instances" SET "catalog" = jsonb_set("catalog", \'{tmp, %s}\', \'%s\') where "id" = %s' % [product["id"], product.to_json.gsub("'", "''"), self.id])
          end
        end

        # Move from tmp to actual
        ActiveRecord::Base.connection.execute('UPDATE "public"."zuora_connect_app_instances" SET "catalog" = jsonb_set("catalog", \'{%{entity}}\', "catalog" #> \'{tmp}\'), "catalog_mapping" = jsonb_set("catalog_mapping", \'{%{entity}}\',  "catalog_mapping" #> \'{tmp}\') where "id" = %{id}' % {:entity => entity_reference, :id => self.id})
        if defined?(Redis.current)
          catalog_keys = Redis.current.smembers("Catalog:#{self.id}:Keys")
          Redis.current.del(catalog_keys.push("Catalog:#{self.id}:Keys"))
        end
        # Clear tmp holder
        ActiveRecord::Base.connection.execute('UPDATE "public"."zuora_connect_app_instances" SET "catalog" = jsonb_set("catalog", \'{tmp}\', \'{}\'), "catalog_mapping" = jsonb_set("catalog_mapping", \'{tmp}\', \'{}\') where "id" = %{id}' % {:id => self.id})

        ActiveRecord::Base.logger = old_logger
        self.update_column(:catalog_updated_at, Time.now.utc)
        self.touch

        # DO NOT RETURN CATALOG. THIS IS NOT SCALABLE WITH LARGE CATALOGS. USE THE  CATALOG_LOOKUP method provided
        return true
      end

      def catalog_outdated?(time: Time.now - 12.hours)
        return self.catalog_updated_at.blank? || (self.catalog_updated_at < time)
      end

      def catalog_loaded?
        return ActiveRecord::Base.connection.execute('SELECT id FROM "public"."zuora_connect_app_instances" WHERE "id" = %s AND catalog = \'{}\' LIMIT 1' % [self.id]).first.nil?
      end

      # Catalog lookup provides method to lookup zuora catalog efficiently.
      # entity_id: If the using catalog json be field to store multiple entity product catalogs.
      # object: The Object class desired to be returned. Available [:product, :rateplan, :charge]
      # object_id: The id or id's of the object/objects to be returned.
      # child_objects: Whether to include child objects of the object in question.
      # cache: Store individual "1" object lookup in redis for caching.
      def catalog_lookup(entity_id: nil, object: :product, object_id: nil, child_objects: false, cache: false)
        entity_reference = entity_id.blank? ? 'Default' : entity_id

        if object_id.present? && ![Array, String].include?(object_id.class)
          raise "Object Id can only be a string or an array of strings"
        end

        if defined?(Redis.current) && object_id.present? && object_id.class == String && object_id.present?
          stub_catalog = cache ? decrypt_data(data: Redis.current.get("Catalog:#{self.id}:#{object_id}:Children:#{child_objects}")) : nil
          object_hierarchy = decrypt_data(data: Redis.current.get("Catalog:#{self.id}:#{object_id}:Hierarchy"))
        end

        if defined?(object_hierarchy)
          object_hierarchy ||= (JSON.parse(ActiveRecord::Base.connection.execute('SELECT catalog_mapping #> \'{%s}\' AS item FROM "public"."zuora_connect_app_instances" WHERE "id" = %s LIMIT 1' % [entity_reference, self.id]).first["item"] || "{}") [object_id] || {"productId" => "SAFTEY", "productRatePlanId" => "SAFTEY", "productRatePlanChargeId" => "SAFTEY"})
        end

        case object
        when :product
          if object_id.nil?
            string =
              "SELECT "\
                "json_object_agg(product_id, product #{child_objects ? '' : '- \'productRatePlans\''}) AS item "\
              "FROM "\
                "\"public\".\"zuora_connect_app_instances\", "\
                "jsonb_each((\"public\".\"zuora_connect_app_instances\".\"catalog\" #> '{%s}' )) AS e(product_id, product) "\
              "WHERE "\
                "\"id\" = %s" % [entity_reference, self.id]
          else
            if object_id.class == String
              string =
                "SELECT "\
                  "(catalog #> '{%s, %s}') #{child_objects ? '' : '- \'productRatePlans\''} AS item "\
                "FROM "\
                  "\"public\".\"zuora_connect_app_instances\" "\
                "WHERE "\
                  "\"id\" = %s" % [entity_reference, object_id.blank? ? BLANK_OBJECT_ID_LOOKUP : object_id, self.id]
            elsif object_id.class == Array
              string =
                "SELECT "\
                  "json_object_agg(product_id, product #{child_objects ? '' : '- \'productRatePlans\''}) AS item "\
                "FROM "\
                  "\"public\".\"zuora_connect_app_instances\", "\
                  "jsonb_each((\"public\".\"zuora_connect_app_instances\".\"catalog\" #> '{%s}' )) AS e(product_id, product) "\
                "WHERE "\
                  "\"product_id\" IN (\'%s\') AND "\
                  "\"id\" = %s" % [entity_reference, object_id.join("\',\'"), self.id]
            end
          end

        when :rateplan
          if object_id.nil?
            string =
              "SELECT "\
                "json_object_agg(rateplan_id, rateplan #{child_objects ? '' : '- \'productRatePlanCharges\''}) AS item "\
              "FROM "\
                "\"public\".\"zuora_connect_app_instances\", "\
                "jsonb_each((\"public\".\"zuora_connect_app_instances\".\"catalog\" #> '{%s}' )) AS e(product_id, product), "\
                "jsonb_each(product #> '{productRatePlans}') AS ee(rateplan_id, rateplan) "\
              "WHERE "\
                "\"id\" = %s" % [entity_reference, self.id]
          else
            if object_id.class == String
              string =
                "SELECT "\
                  "(catalog #> '{%s, %s, productRatePlans, %s}') #{child_objects ? '' : '- \'productRatePlanCharges\''} AS item "\
                "FROM "\
                  "\"public\".\"zuora_connect_app_instances\" "\
                "WHERE "\
                  "\"id\" = %s" % [entity_reference, object_hierarchy['productId'], object_id.blank? ? BLANK_OBJECT_ID_LOOKUP : object_id,  self.id]
            elsif object_id.class == Array
              string =
                "SELECT "\
                  "json_object_agg(rateplan_id, rateplan #{child_objects ? '' : '- \'productRatePlanCharges\''}) AS item "\
                "FROM "\
                  "\"public\".\"zuora_connect_app_instances\", "\
                  "jsonb_each((\"public\".\"zuora_connect_app_instances\".\"catalog\" #> '{%s}' )) AS e(product_id, product), "\
                  "jsonb_each(product #> '{productRatePlans}') AS ee(rateplan_id, rateplan) "\
                "WHERE "\
                  "\"rateplan_id\" IN (\'%s\') AND "\
                  "\"id\" = %s" % [entity_reference, object_id.join("\',\'"), self.id]
            end
          end

        when :charge
          if object_id.nil?
            string =
              "SELECT "\
                "json_object_agg(charge_id, charge) as item "\
              "FROM "\
                "\"public\".\"zuora_connect_app_instances\", "\
                "jsonb_each((\"public\".\"zuora_connect_app_instances\".\"catalog\" #> '{%s}' )) AS e(product_id, product), "\
                "jsonb_each(product #> '{productRatePlans}') AS ee(rateplan_id, rateplan), "\
                "jsonb_each(rateplan #> '{productRatePlanCharges}') AS eee(charge_id, charge) "\
              "WHERE "\
                "\"id\" = %s" % [entity_reference, self.id]
          else
            if object_id.class == String
              string =
                "SELECT "\
                  "catalog #> '{%s, %s, productRatePlans, %s, productRatePlanCharges, %s}' AS item "\
                "FROM "\
                  "\"public\".\"zuora_connect_app_instances\" "\
                "WHERE "\
                  "\"id\" = %s" % [entity_reference, object_hierarchy['productId'], object_hierarchy['productRatePlanId'], object_id.blank? ? BLANK_OBJECT_ID_LOOKUP : object_id , self.id]

            elsif object_id.class == Array
              string =
                "SELECT "\
                  "json_object_agg(charge_id, charge) AS item "\
                "FROM "\
                  "\"public\".\"zuora_connect_app_instances\", "\
                  "jsonb_each((\"public\".\"zuora_connect_app_instances\".\"catalog\" #> '{%s}' )) AS e(product_id, product), "\
                  "jsonb_each(product #> '{productRatePlans}') AS ee(rateplan_id, rateplan), "\
                  "jsonb_each(rateplan #> '{productRatePlanCharges}') AS eee(charge_id, charge) "\
                "WHERE "\
                  "\"charge_id\" IN (\'%s\') AND "\
                  "\"id\" = %s" % [entity_reference, object_id.join("\',\'"), self.id]
            end
          end
        else
          raise "Available objects include [:product, :rateplan, :charge]"
        end

        stub_catalog ||= JSON.parse(ActiveRecord::Base.connection.execute(string).first["item"] || "{}")

        if defined?(Redis.current) && object_id.present? && object_id.class == String && object_id.present?
          if cache
            Redis.current.sadd("Catalog:#{self.id}:Keys", ["Catalog:#{self.id}:#{object_id}:Hierarchy", "Catalog:#{self.id}:#{object_id}:Children:#{child_objects}"])
            Redis.current.set("Catalog:#{self.id}:#{object_id}:Hierarchy", encrypt_data(data: object_hierarchy))
            Redis.current.set("Catalog:#{self.id}:#{object_id}:Children:#{child_objects}", encrypt_data(data: stub_catalog))
          else
            Redis.current.sadd("Catalog:#{self.id}:Keys", ["Catalog:#{self.id}:#{object_id}:Hierarchy"])
            Redis.current.set("Catalog:#{self.id}:#{object_id}:Hierarchy", encrypt_data(data: object_hierarchy))
          end
        end

        return stub_catalog
      end
    ### END Catalog Helping Methods #####

    ### START S3 Helping Methods #####
      def s3_client
        require 'aws-sdk-s3'
        if ZuoraConnect.configuration.mode == "Development"
          @s3_client ||= Aws::S3::Resource.new(region: ZuoraConnect.configuration.aws_region,access_key_id: ZuoraConnect.configuration.dev_mode_access_key_id,secret_access_key: ZuoraConnect.configuration.dev_mode_secret_access_key)
        else
          @s3_client ||= Aws::S3::Resource.new(region: ZuoraConnect.configuration.aws_region)
        end
      end

      def upload_to_s3(local_file,s3_path = nil)
        s3_path = local_file.split("/").last if s3_path.nil?
        obj = self.s3_client.bucket(ZuoraConnect.configuration.s3_bucket_name).object("#{ZuoraConnect.configuration.s3_folder_name}/#{self.id.to_s}/#{s3_path}}")
        obj.upload_file(local_file, :server_side_encryption => 'AES256')
      end

      def get_s3_file_url(key)
        require 'aws-sdk-s3'
        signer = Aws::S3::Presigner.new(client: self.s3_client)
        url = signer.presigned_url(:get_object, bucket: ZuoraConnect.configuration.s3_bucket_name, key: "#{ZuoraConnect.configuration.s3_folder_name}/#{self.id.to_s}/#{key}")
      end
    ### END S3 Helping Methods #####

    ### START Aggregate Grouping Helping Methods ####
      def self.refresh_aggregate_table(aggregate_name: 'all_tasks_processing', table_name: 'tasks', where_clause: "where status in ('Processing', 'Queued')", index_table: true)
        self.update_functions
        if index_table
          ActiveRecord::Base.connection.execute('SELECT "shared_extensions".refresh_aggregate_table(\'%s\', \'%s\', %s, \'Index\');' % [aggregate_name, table_name, ActiveRecord::Base.connection.quote(where_clause)])
        else
          ActiveRecord::Base.connection.execute('SELECT "shared_extensions".refresh_aggregate_table(\'%s\', \'%s\', %s, \'NO\');' % [aggregate_name, table_name, ActiveRecord::Base.connection.quote(where_clause)])
        end
      end

      def self.update_functions
        ActiveRecord::Base.connection.execute(File.read("#{Gem.loaded_specs["zuora_connect"].gem_dir}/app/views/sql/refresh_aggregate_table.txt"))
      end
    ### END Aggregate Grouping Helping Methods #####

    # Overide this method to avoid the new session call for api requests that use the before filter authenticate_app_api_request.
    # This can be usefull for apps that dont need connect metadata call, or credentials, to operate for api requests
    def new_session_for_api_requests(params: {})
      return true
    end

    # Overide this method to avoid the new session call for ui requests that use the before filter authenticate_connect_app_request.
    # This can be usefull for apps that dont need connect metadata call, or credentials, to operate for ui requests
    def new_session_for_ui_requests(params: {})
      return true
    end

    #Method for overiding droping of an app instance
    def drop_instance
      self.drop_message = 'Ok to drop'
      return true
    end

    def reload_attributes(selected_attributes)
      raise "Attibutes must be array" if selected_attributes.class != Array
      value_attributes = self.class.unscoped.where(:id=>id).select(selected_attributes).first.attributes
      value_attributes.each do |key, value|
        next if key == "id" && value.blank?
        self.send(:write_attribute, key, value)
      end
      return self
    end

    def instance_failure(failure)
      raise failure
    end

    def send_email
    end

    def login_lookup(type: "Zuora")
      results = []
      self.logins.each do |name, login|
        results << login if login.tenant_type == type
      end
      return results
    end

    def self.decrypt_response(resp)
      OpenSSL::PKey::RSA.new(ZuoraConnect.configuration.private_key).private_decrypt(resp)
    end

    def attr_builder(field,val)
      singleton_class.class_eval { attr_accessor "#{field}" }
      send("#{field}=", val)
    end

    def method_missing(method_sym, *arguments, &block)
      if method_sym.to_s.include?("login")
        ZuoraConnect.logger.fatal("Method Missing #{method_sym}")
        ZuoraConnect.logger.fatal("Instance Data: #{self.task_data}")
        ZuoraConnect.logger.fatal("Instance Logins: #{self.logins}")
      end
      super
    end

    method_hook :refresh, :updateOption, :update_logins, :before => :check_oauth_state
    method_hook :new_session, :refresh, :build_task, :after => :apartment_switch
  end
end
