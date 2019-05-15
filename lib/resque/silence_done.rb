module Resque  
  module SilenceDone
    def perform_no_log(job)
      begin
        if fork_per_job?
          reconnect
          run_hook :after_fork, job
        end
        job.perform
      rescue Object => e
        report_failed_job(job,e)
      else
        # log_with_severity :info, "done: #{job.inspect}"
      ensure
        yield job if block_given?
      end
    end

    # def work(interval = 5.0, &block)
    #   interval = Float(interval)
    #   startup

    #   loop do
    #     break if shutdown?

    #     unless work_one_job(&block)
    #       break if interval.zero?
    #       log_with_severity :debug, "Sleeping for #{interval} seconds"
    #       procline paused? ? "Paused" : "Waiting for #{queues.join(',')}"
    #       sleep interval
    #     end
    #   end

    #   unregister_worker
    # rescue Exception => exception
    #   return if exception.class == SystemExit && !@child && run_at_exit_hooks
    #   log_with_severity :error, "Failed to start worker : #{exception.inspect}"
    #   unregister_worker(exception)
    # end

    def work_one_job_no_log(job = nil, &block)
      return false if paused?
      return false unless job ||= reserve

      working_on job
      procline "Processing #{job.queue} since #{Time.now.to_i} [#{job.payload_class_name}]"

      #log_with_severity :info, "got: #{job.inspect}"
      job.worker = self

      if fork_per_job?
        perform_with_fork(job, &block)
      else
        perform(job, &block)
      end

      done_working
      true
    end

    def self.included(receiver)
      receiver.class_eval do
        alias work_one_job_with_log work_one_job
        alias work_one_job work_one_job_no_log

        alias perform_with_log perform
        alias perform perform_no_log
      end
    end
  end
end