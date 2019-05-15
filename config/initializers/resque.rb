if defined?(Resque::Worker)
  Resque.send(:extend, Resque::Additions)
  Resque::Worker.send(:include, Resque::DynamicQueues)
  Resque::Worker.send(:include, Resque::SilenceDone) if ZuoraConnect.configuration.silencer_resque_finish == true
  Resque::Job.send(:include, Resque::SelfLookup)
end

Resque.module_eval do
  # Returns a hash, mapping queue names to queue sizes
  def queue_sizes
    paused_queues = Resque.redis.zrange("PauseQueue", 0, -1).map! {|key| key.split("__")[0]}
    queue_names = queues.delete_if{|name| paused_queues.include?(name.split("_")[0])}

    sizes = redis.pipelined do
      queue_names.each do |name|
        redis.llen("queue:#{name}")
      end
    end

    Hash[queue_names.zip(sizes)]
  end
end

if defined?(Resque)
  Resque.logger = ZuoraConnect.custom_logger(name: "Resque", type: 'Monologger', level: MonoLogger::INFO) 
  Resque::Scheduler.logger = ZuoraConnect.custom_logger(name: "ResqueScheduler") if defined?(Resque::Scheduler)
end

Makara::Logging::Logger.logger = ZuoraConnect.custom_logger(name: "Makara") if defined?(Makara)
ElasticAPM.agent.config.logger = ZuoraConnect.custom_logger(name: "ElasticAPM", level: MonoLogger::WARN) if defined?(ElasticAPM) && ElasticAPM.running?
ActionMailer::Base.logger = ZuoraConnect.custom_logger(name: "ActionMailer", type: 'Monologger') if defined?(ActionMailer)
