module Resque
  module SelfLookup
    def payload_class_enhanced
      @payload_class ||= constantize(@payload['class'])
      @payload_class.instance_eval { class << self; self end }.send(:attr_accessor, :worker)
      @payload_class.instance_eval { class << self; self end }.send(:attr_accessor, :job)
      @payload_class.worker =  self.worker
      @payload_class.job =  self
      return @payload_class
    end

    def self.included(receiver)
      receiver.class_eval do
        alias payload_class_old payload_class
        alias payload_class payload_class_enhanced
      end
    end
  end
end
