require 'apartment/migrator'
module ZuoraConnect
  module Controllers
    module Helpers
      extend ActiveSupport::Concern

      def authenticate_app_api_request
        #Skip session for api requests
        Thread.current[:appinstance] = nil
        request.session_options[:skip] = true
        ElasticAPM.set_tag(:trace_id, request.uuid) if defined?(ElasticAPM) && ElasticAPM.running?

        start_time = Time.now
        if request.headers["API-Token"].present?
          @appinstance = ZuoraConnect::AppInstance.where(:api_token => request.headers["API-Token"]).first
          ZuoraConnect.logger.debug("[#{@appinstance.id}] API REQUEST - API token") if @appinstance.present?
          check_instance
        else
          authenticate_or_request_with_http_basic do |username, password|
            @appinstance = ZuoraConnect::AppInstance.where(:token => password).first
            @appinstance ||= ZuoraConnect::AppInstance.where(:api_token => password).first
            ZuoraConnect.logger.debug("[#{@appinstance.id}] API REQUEST - Basic Auth") if @appinstance.present?
            check_instance
          end
        end
        if @appinstance.present?
          ZuoraConnect.logger.debug("[#{@appinstance.id}] Authenticate App API Request Completed In - #{(Time.now - start_time).round(2)}s")
        end
      end

      def verify_with_navbar
        if !session[params[:app_instance_ids]].present?
          host = request.headers["HTTP_X_FORWARDED_HOST"]
          zuora_client = ZuoraAPI::Login.new(url: "https://#{host}")
          menus = zuora_client.get_full_nav(cookies.to_h)["menus"]
          app = menus.select do |item|
            matches = /(?<=.com\/services\/)(.*?)(?=\?|$)/.match(item["url"])
            if !matches.blank?
              matches[0].split("?").first == ENV["DEIS_APP"]
            end
          end

          session[params[:app_instance_ids]] = app[0]
          return app[0]
        else
          return session[params[:app_instance_ids]]
        end
      end

      def select_instance
        begin
          app = verify_with_navbar

          url_tasks = JSON.parse(Base64.urlsafe_decode64(CGI.parse(URI.parse(app["url"]).query)["app_instance_ids"][0]))
          @app_instance_ids = JSON.parse(Base64.urlsafe_decode64(params[:app_instance_ids]))

          if (url_tasks & @app_instance_ids).size == @app_instance_ids.size
            sql = "select name,id from zuora_connect_app_instances where id = ANY(ARRAY#{@app_instance_ids})"
            result = ActiveRecord::Base.connection.execute(sql)
            @names = {}
            result.each do |x|
              @names[x["id"].to_i] = x["name"]
            end
            render "zuora_connect/static/launch"
          else
            render "zuora_connect/static/invalid_launch_request"
          end
        rescue => ex
          ZuoraConnect.logger.debug("Error parsing Instance ID's: #{ex.message}")
          render "zuora_connect/static/invalid_launch_request"
        end
      end

      def authenticate_connect_app_request
        ElasticAPM.set_tag(:trace_id, request.uuid) if defined?(ElasticAPM) && ElasticAPM.running?
        Thread.current[:appinstance] = nil
        if params[:app_instance_ids].present? && !params[:app_instance_id].present?
          begin
            app_instance_ids = JSON.parse(Base64.urlsafe_decode64(params[:app_instance_ids]))
            if app_instance_ids.length == 1
              verify_with_navbar
              instances = JSON.parse(Base64.urlsafe_decode64(CGI.parse(URI.parse(session[params[:app_instance_ids]]["url"]).query)["app_instance_ids"][0]))
              if instances.include?(app_instance_ids[0])
                @appinstance = ZuoraConnect::AppInstance.find(app_instance_ids[0])
                @appinstance.new_session(session: {})
                @appinstance.cache_app_instance
                session["appInstance"] = app_instance_ids[0]
              else
                ZuoraConnect.logger.error("Launch Error: Param Instance didnt match session data")
                render "zuora_connect/static/invalid_launch_request"
                return
              end
            else
              select_instance
              return
            end
          rescue => ex
            ZuoraConnect.logger.error(ex)
            render "zuora_connect/static/invalid_launch_request"
            return
          end
          
        elsif params[:app_instance_ids].present? && params[:app_instance_id].present?
          begin
            instances = JSON.parse(Base64.urlsafe_decode64(CGI.parse(URI.parse(session[params[:app_instance_ids]]["url"]).query)["app_instance_ids"][0]))
            if instances.include?(params[:app_instance_id].to_i)
              @appinstance = ZuoraConnect::AppInstance.find(params[:app_instance_id].to_i)
              @appinstance.new_session(session: {})
              @appinstance.cache_app_instance
              session["appInstance"] = params[:app_instance_id].to_i
            else
              render "zuora_connect/static/invalid_launch_request"
              return
            end
          rescue => ex
            ZuoraConnect.logger.error(ex)
            render "zuora_connect/static/invalid_launch_request"
            return
          end
        end
        start_time = Time.now
        if ZuoraConnect.configuration.mode == "Production"
          if request["data"] && /^([A-Za-z0-9+\/\-\_]{4})*([A-Za-z0-9+\/]{4}|[A-Za-z0-9+\/]{3}=|[A-Za-z0-9+\/]{2}==)$/.match(request["data"].to_s)
            setup_instance_via_data
          else
            setup_instance_via_session
          end
        else
          setup_instance_via_dev_mode
        end
        #Call .data_lookup with the current session to retrieve session. In some cases session may be stored/cache in redis 
        #so data lookup provides a model method that can be overriden per app.
        if params[:controller] != 'zuora_connect/api/v1/app_instance' && params[:action] != 'drop'
          if @appinstance.new_session_for_ui_requests(:params => params)
            @appinstance.new_session(:session => @appinstance.data_lookup(:session => session))
          end
        end
        if session["#{@appinstance.id}::user::email"].present? 
          ElasticAPM.set_user(session["#{@appinstance.id}::user::email"])  if defined?(ElasticAPM) && ElasticAPM.running?
          PaperTrail.whodunnit =  session["#{@appinstance.id}::user::email"] if defined?(PaperTrail)
        end
        begin
          I18n.locale = session["#{@appinstance.id}::user::locale"] ?  session["#{@appinstance.id}::user::locale"] : @appinstance.locale
        rescue I18n::InvalidLocale => ex
          ZuoraConnect.logger.error(ex) if !ZuoraConnect::AppInstance::IGNORED_LOCALS.include?(ex.locale.to_s.downcase)
        end
        Time.zone = session["#{@appinstance.id}::user::timezone"] ? session["#{@appinstance.id}::user::timezone"] : @appinstance.timezone
        ZuoraConnect.logger.debug("[#{@appinstance.blank? ? "N/A" : @appinstance.id}] Authenticate App Request Completed In - #{(Time.now - start_time).round(2)}s")
      end

      def persist_connect_app_session
        if @appinstance.present?
          if defined?(Redis.current)
            @appinstance.cache_app_instance
          else
            session.merge!(@appinstance.save_data)
          end
        end
      end

      def check_connect_admin!
        raise ZuoraConnect::Exceptions::AccessDenied.new("User is not an authorized admin for this application") if !session["#{@appinstance.id}::admin"]
      end

      def check_connect_admin
        return session["#{@appinstance.id}::admin"]
      end

    private
      def setup_instance_via_data
        session.clear
        values = JSON.parse(ZuoraConnect::AppInstance.decrypt_response(Base64.urlsafe_decode64(request["data"])))
        if values["param_data"]
          values["param_data"].each do |k ,v|
            params[k] = v
          end
        end
        session["#{values["appInstance"]}::destroy"] = values["destroy"]
        session["appInstance"] = values["appInstance"]
        if values["current_user"]
          session["#{values["appInstance"]}::admin"] = values["current_user"]["admin"] ? values["current_user"]["admin"] : false
          session["#{values["appInstance"]}::user::timezone"] = values["current_user"]["timezone"]
          session["#{values["appInstance"]}::user::locale"] = values["current_user"]["locale"]
          session["#{values["appInstance"]}::user::email"] = values["current_user"]["email"]
        end

        ZuoraConnect.logger.debug({msg: 'Setup values', connect: values}) if Rails.env != "production"

        @appinstance = ZuoraConnect::AppInstance.where(:id => values["appInstance"].to_i).first
        if @appinstance.blank?
          Apartment::Tenant.switch!("public")
          begin
            Apartment::Tenant.create(values["appInstance"].to_s)
          rescue Apartment::TenantExists => ex
            ZuoraConnect.logger.debug("Tenant Already Exists")
          end
          @appinstance = ZuoraConnect::AppInstance.new(:api_token =>  values[:api_token],:id => values["appInstance"].to_i, :access_token => values["access_token"].blank? ? values["user"] : values["access_token"], :token => values["refresh_token"]  , :refresh_token => values["refresh_token"].blank? ? values["key"] : values["refresh_token"], :oauth_expires_at => values["expires"])
          @appinstance.save(:validate => false)
        else
          @appinstance.access_token = values["access_token"] if !values["access_token"].blank? && @appinstance.access_token != values["access_token"]
          @appinstance.refresh_token = values["refresh_token"] if !values["refresh_token"].blank? && @appinstance.refresh_token != values["refresh_token"]
          @appinstance.oauth_expires_at = values["expires"] if !values["expires"].blank?
          @appinstance.api_token = values["api_token"] if !values["api_token"].blank? && @appinstance.api_token != values["api_token"]
          if @appinstance.access_token_changed? && @appinstance.refresh_token_changed?
            @appinstance.save(:validate => false)
          else
            raise ZuoraConnect::Exceptions::AccessDenied.new("Authorization mistmatch. Possible tampering")
          end
        end     
      end

      def setup_instance_via_session
        if session["appInstance"].present?
          @appinstance = ZuoraConnect::AppInstance.where(:id => session["appInstance"]).first
        else
          raise ZuoraConnect::Exceptions::SessionInvalid.new("Session Blank -- Relaunch Application")
        end
      end

      def setup_instance_via_dev_mode
        session["appInstance"] = ZuoraConnect.configuration.dev_mode_appinstance
        user = ZuoraConnect.configuration.dev_mode_user
        key = ZuoraConnect.configuration.dev_mode_pass
        values = {:user => user , :key => key, :appinstance => session["appInstance"]}
        @appinstance = ZuoraConnect::AppInstance.where(:id => values[:appinstance].to_i).first
        if @appinstance.blank?
          Apartment::Tenant.switch!("public")
          begin
            Apartment::Tenant.create(values[:appinstance].to_s)
          rescue Apartment::TenantExists => ex
            Apartment::Tenant.drop(values[:appinstance].to_s)
            retry
          end

          @appinstance = ZuoraConnect::AppInstance.new(:id => values[:appinstance].to_i, :access_token => values[:user], :refresh_token => values[:key], :token => "#{values[:key]}#{values[:key]}", :api_token => "#{values[:key]}#{values[:key]}")
          @appinstance.save(:validate => false)
        end
        if @appinstance.access_token.blank? || @appinstance.refresh_token.blank? || @appinstance.token.blank? || @appinstance.api_token.blank?
          @appinstance.update_attributes!(:access_token =>  values["user"], :refresh_token =>  values["key"], :token => "#{values[:key]}#{values[:key]}", :api_token => "#{values[:key]}#{values[:key]}")
        end
        session["#{@appinstance.id}::admin"] =  ZuoraConnect.configuration.dev_mode_admin
      end

      #API ONLY
      def check_instance
        if @appinstance.present?
          if @appinstance.new_session_for_api_requests(:params => params)
            @appinstance.new_session(:session => @appinstance.data_lookup(:session => session))
          end
          Thread.current[:appinstance] = @appinstance
          PaperTrail.whodunnit = "API User" if defined?(PaperTrail)
          ElasticAPM.set_user("API User")  if defined?(ElasticAPM) && ElasticAPM.running?
          return true
        else
          render text: "Access Denied", status: :unauthorized
        end
      end
    end
  end
end
