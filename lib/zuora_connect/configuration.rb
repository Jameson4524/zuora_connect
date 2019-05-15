module ZuoraConnect
  class Configuration

    attr_accessor :default_locale, :default_time_zone, :url, :mode, :delayed_job,:private_key, :additional_apartment_models

    attr_accessor :enable_metrics, :telegraf_endpoint, :telegraf_debug, :custom_prometheus_update_block, :silencer_resque_finish, :blpop_queue

    attr_accessor :oauth_client_id, :oauth_client_secret, :oauth_client_redirect_uri

    attr_accessor :dev_mode_logins, :dev_mode_options, :dev_mode_mode, :dev_mode_appinstance, :dev_mode_user, :dev_mode_pass, :dev_mode_admin, :dev_mode_secret_access_key,:dev_mode_access_key_id,:aws_region, :s3_bucket_name, :s3_folder_name

    def initialize
      @default_locale = :en
      @default_time_zone = Time.zone
      @url = "https://connect.zuora.com"
      @mode = "Production"
      @delayed_job = false
      @private_key = ENV["CONNECT_KEY"]
      @additional_apartment_models = []
      @silencer_resque_finish = true
      @blpop_queue = false

      # Setting the app name for telegraf write
      @enable_metrics = false
      @telegraf_endpoint = 'udp://telegraf-app-metrics.monitoring.svc.cluster.local:8094'
      @telegraf_debug = false
      # OAuth Settings
      @oauth_client_id = ""
      @oauth_client_secret = ""
      @oauth_client_redirect_uri = "https://connect.zuora.com/"

      # DEV MODE OPTIONS
      @dev_mode_logins = { "target_login" => {"tenant_type" => "Zuora", "username" => "user", "password" => "pass", "url" => "url"} }
      @dev_mode_options = {"name" => {"config_name" => "name", "datatype" => "type", "value" => "value"}}
      @dev_mode_mode = "Universal"
      @dev_mode_appinstance = "1"
      @dev_mode_user = "test"
      @dev_mode_pass = "test"
      @dev_mode_admin = false
      @dev_mode_secret_access_key = nil
      @dev_mode_access_key_id = nil
      @aws_region = "us-west-2"
      @s3_bucket_name = "rbm-apps"
      @s3_folder_name = Rails.application.class.parent_name
    end

    def private_key
      raise "Private Key Not Set" if @private_key.blank?
      @private_key.include?("BEGIN") ? @private_key : Base64.urlsafe_decode64(@private_key)
    end
  end
end
