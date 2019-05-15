module Resque
  module DynamicQueues
    def filter_busy_queues qs
      busy_queues = Resque::Worker.working.map { |worker| worker.job["queue"] }.compact
      Array(qs.dup).compact - busy_queues
    end

    def rotated_queues
      @n ||= 0
      @n += 1
      rot_queues = queues # since we rely on the resque-dynamic-queues plugin, this is all the queues, expanded out
      if rot_queues.size > 0
        @n = @n % rot_queues.size
        rot_queues.rotate(@n)
      else
        rot_queues
      end
    end

    def queue_depth queuename
      busy_queues = Resque::Worker.working.map { |worker| worker.job["queue"] }.compact
      # find the queuename, count it.
      busy_queues.select {|q| q == queuename }.size
    end

    def get_categorized_queues(queue_list)
      priority_map = {"Synchronous" => 0, "High" => 1, "Medium" => 2, "Low" => 3}
      categorized_queues = {}
      for queue in queue_list.uniq
        priority = queue.split("_")[1]
        priority = "Medium" if !["Synchronous", "High", "Medium", "Low"].include?(priority)
        categorized_queues[priority] ||= []
        categorized_queues[priority].push(queue)
      end
      return categorized_queues.transform_keys{ |key| priority_map[key.to_s]}.sort
    end

    DEFAULT_QUEUE_DEPTH = 0
    def should_work_on_queue? queuename
      return true if @queues.include? '*'  # workers with QUEUES=* are special and are not subject to queue depth setting
      max = DEFAULT_QUEUE_DEPTH
      unless ENV["RESQUE_QUEUE_DEPTH"].nil? || ENV["RESQUE_QUEUE_DEPTH"] == ""
        max = ENV["RESQUE_QUEUE_DEPTH"].to_i
      end
      return true if max == 0 # 0 means no limiting
      cur_depth = queue_depth(queuename)
      log! "queue #{queuename} depth = #{cur_depth} max = #{max}"
      return true if cur_depth < max
      false
    end

    def get_grouped_queues
      self.queues.sort.group_by{|u| /(\d{1,20})_.*/.match(u) ? /(\d{1,20})_.*/.match(u).captures.first : nil}
    end

    def reserve_with_round_robin
      grouped_queues = self.get_grouped_queues

      #Instance queue grouping
      if !grouped_queues.keys.include?(nil) && grouped_queues.keys.size > 0
        if ZuoraConnect.configuration.blpop_queue
          @job_in_progress = get_restricted_job
          return @job_in_progress if @job_in_progress.present?
          return @job_in_progress = get_queued_job(grouped_queues)
        else
          @n ||= 0       
          @n += 1
          @n = @n % grouped_queues.keys.size
          grouped_queues.keys.rotate(@n).each do |key|
            self.get_categorized_queues(grouped_queues[key]).each do |key, queues|
              queues.each do |queue|
                log! "Checking #{queue}"
                if should_work_on_queue?(queue) && @job_in_progress = Resque::Job.reserve(queue)
                  log! "Found job on #{queue}"
                  return @job_in_progress
                end
              end
            end
            @n += 1 # Start the next search at the queue after the one from which we pick a job.
          end
          nil
        end
      else 
        return reserve_without_round_robin
      end
      
    rescue Exception => e
      log "Error reserving job: #{e.inspect}"
      log e.backtrace.join("\n")
      raise e
    end

    def create_job(queue, payload)
      return unless payload
      Resque::Job.new(queue, payload)
    end

    def get_next_job(grouped_queues)
      @n ||= 1
      queue_index = {}
      grouped_queues.each_with_index do |(key, queue_list), index|
        queue_list.each do |queue|
          queue_index[queue] = index
        end
      end

      grouped_queues = grouped_queues.values.rotate(@n).map{|queue_list| get_categorized_queues(queue_list).to_h.values.flatten}.flatten.delete_if{|queue| !should_work_on_queue?(queue)}.map{|queue| "queue:#{queue}"}
      queue, payload = Resque.redis.blpop(grouped_queues, :timeout => (ENV["BLPOP_TIMEOUT"].to_i || 30))
      return nil if queue.blank?
      
      queue = queue.split("queue:")[1]
      @n = queue_index[queue] + 1
      return create_job(queue, Resque.decode(payload))      
    end

    def get_restricted_job
      Resque::Plugins::ConcurrentRestrictionJob.next_runnable_job_random
    end

    def get_queued_job(grouped_queues)
      if defined?(Resque::Plugins::ConcurrentRestriction)
        # Bounded retry
        1.upto(Resque::Plugins::ConcurrentRestriction.reserve_queued_job_attempts) do |i|
          resque_job = get_next_job(grouped_queues)

          # Short-curcuit if a job was not found
          return if resque_job.nil?

          # If there is a job on regular queues, then only run it if its not restricted
          job_class = resque_job.payload_class
          job_args = resque_job.args

          # Return to work on job if not a restricted job
          return resque_job unless job_class.is_a?(Resque::Plugins::ConcurrentRestriction)

          # Keep trying if job is restricted. If job is runnable, we keep the lock until
          # done_working
          return resque_job unless job_class.stash_if_restricted(resque_job)
        end
        
        # Safety net, here in case we hit the upper bound and there are still queued items
        return nil        
      else
        return get_next_job(grouped_queues)
      end
    end

    # Returns a list of queues to use when searching for a job.
    #
    # A splat ("*") means you want every queue (in alpha order) - this
    # can be useful for dynamically adding new queues.
    #
    # The splat can also be used as a wildcard within a queue name,
    # e.g. "*high*", and negation can be indicated with a prefix of "!"
    #
    # An @key can be used to dynamically look up the queue list for key from redis.
    # If no key is supplied, it defaults to the worker's hostname, and wildcards
    # and negations can be used inside this dynamic queue list.   Set the queue
    # list for a key with Resque.set_dynamic_queue(key, ["q1", "q2"]
    #
    def queues_with_dynamic
      queue_names = @queues.dup
      
      return queues_without_dynamic if queue_names.grep(/(^!)|(^@)|(\*)/).size == 0

      real_queues = Resque.queues
      matched_queues = []

      #Remove Queues under Api Limits
      Redis.current.zremrangebyscore("APILimits", "0", "(#{Time.now.to_i}")
      api_limit_instances = Redis.current.zrange("APILimits", 0, -1).map {|key| key.to_i if key.match(/^\d*$/)}.compact
      real_queues = real_queues.select {|key| key if !api_limit_instances.include?((key.match(/^(\d*)_.*/) || [])[1].to_i)} ## 2
        
      #Queue Pausing 
      Resque.redis.zremrangebyscore("PauseQueue", "0", "(#{Time.now.to_i}")
      paused_instances = Resque.redis.zrange("PauseQueue", 0, -1).map {|key| key.split("__")[0].to_i if key.match(/^\d*__.*/)}.compact
      real_queues = real_queues.select {|key| key if !paused_instances.include?((key.match(/^(\d*)_.*/) || [])[1].to_i)}

      while q = queue_names.shift
        q = q.to_s

        if q =~ /^(!)?@(.*)/
          key = $2.strip
          key = hostname if key.size == 0

          add_queues = Resque.get_dynamic_queue(key)
          add_queues.map! { |q| q.gsub!(/^!/, '') || q.gsub!(/^/, '!') } if $1

          queue_names.concat(add_queues)
          next
        end

        if q =~ /^!/
          negated = true
          q = q[1..-1]
        end

        patstr = q.gsub(/\*/, '.*')
        pattern = /^#{patstr}$/
        if negated
          matched_queues -= matched_queues.grep(pattern)
        else
          matches = real_queues.grep(/^#{pattern}$/)
          matches = [q] if matches.size == 0 && q == patstr
          matched_queues.concat(matches.sort)
        end
      end
     
      return matched_queues.uniq
    end


    def self.included(receiver)
      receiver.class_eval do
        alias queues_without_dynamic queues
        alias queues queues_with_dynamic
        alias reserve_without_round_robin reserve
        alias reserve reserve_with_round_robin
      end
    end
  end
end