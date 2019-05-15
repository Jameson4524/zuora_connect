module ZuoraConnect
  class StaticController < ApplicationController
    before_action :authenticate_connect_app_request, :except => [:metrics, :health, :session_error, :invalid_app_instance_error, :initialize_app]
    before_action :clear_connect_app_session,        :only =>   [:metrics, :health, :session_error, :invalid_app_instance_error, :initialize_app]
    after_action :persist_connect_app_session,       :except => [:metrics, :health, :session_error, :invalid_app_instance_error, :initialize_app]
    
    skip_before_action :verify_authenticity_token, :only => [:initialize_app]

    def session_error
      respond_to do |format|
        format.html
        format.json { render json: { message: "Session Error", status: 500 }, status: 500 }
      end
    end

    def invalid_app_instance_error
      respond_to do |format|
        format.html
        format.json {render json: { message: "Invalid App Instance", status: 500 }, status: 500 }
      end
    end

    def metrics
      type = params[:type].present? ? params[:type] : "versions"
      render json: ZuoraConnect::AppInstance.get_metrics(type).to_json, status: 200
    end

    def health
      if params[:error].present?
        begin 
          raise ZuoraConnect::Exceptions::Error.new('This is an error')
        rescue => ex
          case params[:error]
          when 'Log'  
            Rails.logger.error(ex)
          when 'Exception'
            raise
          end
        end
      end

      render json: {
        message: "Alive",
        status: 200
      }, status: 200
    end

    def initialize_app
      begin
        authenticate_connect_app_request
        render json: {
          message: "Success",
          status: 200
        }, status: 200
      rescue
        render json: {
          message: "Failure initializing app instance",
          status: 500
        }, status: 500
      end
    end

    private

    def clear_connect_app_session
      Thread.current[:appinstance] = nil
      request.session_options[:skip] = true
    end

  end
end
