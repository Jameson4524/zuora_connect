$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "zuora_connect/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "zuora_connect"
  s.version     = ZuoraConnect::VERSION
  s.authors     = ["Connect Team"]
  s.email       = ["connect@zuora.com"]
  s.summary     = "Summary of Connect."
  s.description = "Description of Connect."

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.rdoc"]
  s.test_files = Dir["test/**/*"]

  s.add_dependency "apartment"
  s.add_dependency "ougai"
  s.add_dependency "zuora_api", '~> 1.6.21', '>= 1.6.21'
  s.add_dependency "httparty", "~> 0.16.4", '>= 0.16.4'
  s.add_dependency "bundler", "~> 1.12"
  s.add_dependency "lograge"
  s.add_dependency 'aws-sdk-s3'
  s.add_dependency "mono_logger", "~> 1.0"
  s.add_dependency("railties", ">= 4.1.0", "< 5.3")
  s.add_dependency "raindrops"

  s.add_development_dependency "rspec", "~> 3.0"
  s.add_development_dependency "rspec-rails"
  s.add_development_dependency "rspec-expectations"
  s.add_development_dependency "factory_bot"
  s.add_development_dependency "derailed"
  s.add_development_dependency "pg"
  s.add_development_dependency "webmock"
  s.add_development_dependency "fakeredis"
end
