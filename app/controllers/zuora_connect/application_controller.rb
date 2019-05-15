module ZuoraConnect
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception
    before_action :authenticate_connect_app_request
    after_action :persist_connect_app_session

  end
end
