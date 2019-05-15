redis_url = ENV["REDIS_URL"].present? ?  ENV["REDIS_URL"] : defined?(Rails.application.secrets.redis) ? Rails.application.secrets.redis : 'redis://localhost:6379/1'
resque_url = ENV["RESQUE_URL"].present? ?  ENV["RESQUE_URL"] : defined?(Rails.application.secrets.resque) ? Rails.application.secrets.resque : 'redis://localhost:6379/1'
if defined?(Redis.current)
  Redis.current = Redis.new(:id => "#{ZuoraConnect::Telegraf.full_process_name(process_name: 'Redis')}", :url => redis_url, :timeout => 6, :reconnect_attempts => 2)
  if defined?(Resque.redis)
    Resque.redis = resque_url != redis_url ? Redis.new(:id => "#{ZuoraConnect::Telegraf.full_process_name(process_name: 'Resque')}", :url => resque_url, :timeout => 6, :reconnect_attempts => 2) : Redis.current
  end
end
if defined?(RedisBrowser)
  RedisBrowser.configure("connections" => { 
  	"Redis" => { "url" => redis_url },
  	"Resque" => { "url" => resque_url }})
end
