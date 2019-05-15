if defined?(Unicorn::WorkerKiller)
  Unicorn::WorkerKiller.module_eval do
    self.singleton_class.send(:alias_method, :kill_self_old, :kill_self)
    def self.kill_self(logger, start_time)
      self.kill_self_old(logger, start_time)
      ZuoraConnect::AppInstance.write_to_telegraf(direction: 'Unicorn-Killer', tags: {app_instance: 0}, values: {kill: 1})
    end
  end
end