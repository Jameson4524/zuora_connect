module ZuoraConnect
  module Views
    module Helpers
      def is_app_admin?
        return @appinstance.blank? ? false : session["#{@appinstance.id}::admin"]
      end
    end
  end
end
