require_dependency "zuora_connect/application_controller"

module ZuoraConnect
  class Api::V1::AppInstanceController < ApplicationController

    def create
      Apartment::Tenant.create(session['AppInstance'])
      respond_to do |format|
        format.json {render :json => "Created"}
      end
    end

    def drop
      instance_id = @appinstance.id
      if session["#{instance_id}::destroy"] && ZuoraConnect::AppInstance.where(:id => instance_id).size != 0
        if @appinstance.drop_instance
          ZuoraConnect::AppInstance.destroy(instance_id)
          msg = Apartment::Tenant.drop(instance_id)

          respond_to do |format|
            if msg.error_message.present?
              format.json {render json: {"message" => msg.error_message}, status: :bad_request }
            else
              format.json {render json: {}, status: :ok}
            end
          end
        else
          respond_to do |format|
            format.json {render json: {"message" => @appinstance.drop_message}, status: :bad_request}
          end
        end
      else
        respond_to do |format|
          format.json { render json: { "message" => "Unauthorized"}, status:  :unauthorized }
        end
      end
    end

    def status


    end

    def cache_bust
      if defined?(Redis.current)
        Redis.current.del("AppInstance:#{@appinstance.id}")
        respond_to do |format|
          format.json {render json: {}, status: :ok}
        end
      else
        respond_to do |format|
          format.json {render json: {}, status: :bad_request}
        end
      end
    end

  end
end
