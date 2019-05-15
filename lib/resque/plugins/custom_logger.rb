# This Resque extension changes the resque default logger to monologger
# and formats the log in json format.
# 
# Monologger supports printing logs in trap block.
# 
module Resque
  module Plugins
    module CustomLogger
      def before_perform(*args)
        Rails.logger.with_fields = { trace_id: SecureRandom.uuid, name: "RailsWorker"} if Rails.logger.class.to_s == 'Ougai::Logger'
        case args.class.to_s
        when "Array"
          if args.first.class == Hash
            data = args.first.merge({:worker_class => self.to_s})
          else
            data = {:worker_class => self.to_s, :args => args}
          end
        when "Hash"
          data = args.merge({:worker_class => self.to_s})
        end
        data = {:msg => 'Starting job', :job => data}
        data.merge!({:app_instance_id => data.dig(:job, 'app_instance_id')}) if data.dig(:job, 'app_instance_id').present?
        Rails.logger.info(data) if data.present?
      end
    end
  end
end