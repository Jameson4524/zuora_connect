require_dependency "zuora_connect/application_controller"

module ZuoraConnect
  class Admin::TenantController < ApplicationController
    before_action :check_admin
    def index

    end

  end
end
