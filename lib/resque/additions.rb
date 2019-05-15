module Resque
  module Additions
    def dequeue_from(queue, klass, *args)
      ####### ------ Resque Job --------
      # Perform before_dequeue hooks. Don't perform dequeue if any hook returns false
      before_hooks = Plugin.before_dequeue_hooks(klass).collect do |hook|
        klass.send(hook, *args)
      end
      return if before_hooks.any? { |result| result == false }

      destroyed = Job.destroy(queue, klass, *args)

      Plugin.after_dequeue_hooks(klass).each do |hook|
        klass.send(hook, *args)
      end

      destroyed
    end
    
    ####### ------ Resque Delayed Job --------
    # Returns delayed jobs schedule timestamp for +klass+, +args+.
    def scheduled_at_with_queue(queue, klass, *args)
      search = encode(job_to_hash_with_queue(queue,klass, args))
      redis.smembers("timestamps:#{search}").map do |key|
        key.tr('delayed:', '').to_i
      end
    end

    # Given an encoded item, remove it from the delayed_queue
    def remove_delayed_with_queue(queue, klass, *args)
      search = encode(job_to_hash_with_queue(queue,klass, args))
      remove_delayed_job(search)
    end

    #Given a timestamp and job (klass + args) it removes all instances and
    # returns the count of jobs removed.
    #
    # O(N) where N is the number of jobs scheduled to fire at the given
    # timestamp
    def remove_delayed_job_with_queue_from_timestamp(timestamp, queue, klass, *args)
      return 0 if Resque.inline?

      key = "delayed:#{timestamp.to_i}"
      encoded_job = encode(job_to_hash_with_queue(queue, klass, args))

      redis.srem("timestamps:#{encoded_job}", key)
      count = redis.lrem(key, 0, encoded_job)
      clean_up_timestamp(key, timestamp)

      count
    end
  end
end