module ZuoraConnect
  class RequestIdMiddleware
    mattr_accessor :request_id
    mattr_accessor :zuora_request_id

    def initialize(app)
      @app = app
    end

    def call(env)
      self.request_id = env['action_dispatch.request_id']
      self.zuora_request_id = env["HTTP_ZUORA_REQUEST_ID"]
      @app.call(env)
    end
  end
end