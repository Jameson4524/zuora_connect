# Connect Gem

[![Gem Version](https://badge.fury.io/rb/zuora_connect.svg)](https://badge.fury.io/rb/zuora_connect)

## Requirements
This gem requires a postgres database

## Install

Add this line to your application's Gemfile:

```ruby
gem 'zuora_connect'
```

Then execute `bundle install` in your terminal

## Configuration

### Settings
This gem can be configured by adding `connect.rb` to the `config/initializers` folder. An example file and the available options can be seen below.
```ruby
ZuoraConnect.configure do |config|
  config.url = ""
  config.delayed_job = false
  config.default_time_zone = Time.zone
  config.default_locale = :en
  config.timeout = 5.minutes
  config.private_key = ""
  config.mode = "Production"
  config.dev_mode_logins = { "target_login" => {"tenant_type" => "Zuora", "username" => "user", "password" => "pass", "url" => "url"} }
  config.dev_mode_options = {"name" => {"config_name" => "name", "datatype" => "type", "value" => "value"}}
  config.dev_mode_mode = "Universal"
end
```

|        Option        |                         Description                         | Required |                                      Values                                            |           Default           |                  Example                   |
| -------------------- | ----------------------------------------------------------- | -------- | -------------------------------------------------------------------------------------- | --------------------------- | ------------------------------------------ |
| url                  | URL for the gem to connect to                               | Optional | https://connect.zuora.com <br/> https://connect-staging.zuora.com <br/> localhost:3000 | "https://connect.zuora.com" | config.url = `"https://connect.zuora.com"` |
| delayed_job          | Used to indicate if Delayed Job is used by this Application | Optional | true or false | `true`| `config.delayed_job - true`|
| default_time_zone    | Used to indicate the default timezone for the application   | Optional | A valid time zone object | `Time.zone`| `config.default_time_zone = Time.zone`     |
| default_locale       | Used to indicate the default locale for the application     | Optional | A valid locale| `:en`| `config.default_locale = :en`|
| private_key| Used to indicate the private key to use when decrypting the data payload|Required for Production| A valid private key| `nil`|`config.private_key = File.open(#{Rails.root/private_key})`|
| timeout|Used to indicate the amount of time the current session stays active before syncing with ZuoraConnect| Optional |ActiveSupport::Duration |`5.minutes`|`config.timeout = 1.hour`|
| mode|Used to indicate current environment the gem should run against|Optional |Production or Development|`"Production"`|`config.mode = "Development"`|
| dev_mode_appinstance|Used to indicate the schema name to use when in development mode|Optional|String|`"1"` |`config.dev_mode_appinstance = "1"`|
| dev_mode_admin|Used to indicate if admin mode should be turned on in development mode. This will cause all admin calls to be evaluated to true when displaying admin only elements in your application.|Optional|true or false|`false`|`config.dev_mode_admin = true`|
| dev_mode_pass|Used to mock up the users ZuoraConnect password|Optional |String|`"Test"`|`config.dev_mode_pass = "password1"`|
| dev_mode_user|Used to mock up the users ZuoraConnect username|Optional|String|`"Test"`|`config.dev_mode_user = "User1"`|
| dev_mode_logins|Used to mock up the login payload from ZuoraConnect|Optional|Hash|`nil`| `config.dev_mode_logins=  { "target_login" => {"tenant_type" => "Zuora","username" => "user","password" => "pass","url" => "url"}}`
| dev_mode_mode|Used to mock up the mode passed from ZuoraConnect|Optional |String|`"Universal" `|`config.dev_mode_mode = "Mode2"`|
| dev_mode_options|Used to mock up the options payload from ZuoraConnect|Optional |Hash|`nil`|'config.dev_mode_options ={"name" => {"config_name" => "name","datatype" => "type","value" => "value"}}'|


### Controller Setup
The following controllers should have the below lines added to them

#### Application Controller ( `controllers/application_controller.rb`)
```ruby
before_action :authenticate_connect_app_request
after_action :persist_connect_app_session
```

#### Admin controllers
```ruby
before_action :check_connect_admin!
```

#### Admin actions inside a controllers

```ruby
before_action :check_connect_admin!, :only => [:logs]
```
#### API Controller
```ruby
before_action :authenticate_app_api_request
```

An explanation of the available before_filters and what they do can be found below

|             Name             |                                                                                                                                       Description                                                                                                                                       |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| authenticate_app_api_request | Authenticates the incoming request, handles data segmentation, and creates the @appinstance global variable                                                                                                                                                                             |
| persist_connect_app_session  | Saves the current user session for use after every request so that every request does not require authentication with Connect. Instead authentication to Connect is done based on the timeout value of the session set in the configuration steps above                                 |
| check_connect_admin          | Checks if the user is labeled as an admin as deemed by the encrypted request payload coming from Connect. This filter is used to lock down certain functionality that only the Developer should have access to. <br/> Returns false if the user is not an admin                          |
| check_connect_admin!         | The filter works the same as the above but instead raises an exception `ZuoraConnect::Exceptions::AccessDenied`                                                                                                                                                                         |
| authenticate_app_api_request | Authenticates the incoming API request based on the token passed in. The token must match a token associate to one of the available app instances. This token is stored on the app instance object as api_token. More information can be found in the API authentication section below. |

## Usage

The Connect gem provides an integration with ZuoraConnect by allowing the application to read data from Connect and make the appropriate API calls.

### Data Segmentation

The Connect Gem provides an integration with ZuoraConnect by allowing the application to read data from Connect and make the appropriate API calls.

### The App Instance object

#### Methods and Attributes

|     Name     |    Type     | Description  |           Example           |
| ------------ | ----------- | ------------ | --------------------------- |
| new_session  | `Method`    |              | @appinstance.new_sesion     |
| updateOption | `Method`    |              | @appinstance.updateOption() |
| options      | `Attribute` |              | @appinstance.options        |
| mode         | `Attribute` |              | @appinstance.mode           |
| logins       | `Attribute` |              | @appinstance.logins         |
| task_data    | `Attribute` |              | @appinstance.task_data      |
| token        | `Attribute` | `DEPRECATED` | @appinstance.token          |
| api_token    | `Attribute` |              | @appinstance.api_token      |

#### Accessing the Object

The `@appinstance` object is accessible in every View and Controller in your application. In order to access `@appinstance` in a Model it must be pulled out of the current thread by doing the following:
```ruby
@appinstance = Thread.current[:appinstance]
```
### Login Object

All Login information available to your app is passed from connect in a hash in the form `{:target_login => data, :source_login => data}`. It is important to note that target_login and source_login can be variable and that any number of logins can be passed to your application as defined by Connect. For example the following use case could exist: `{:zuora_login => data, :system1_login => data,:system2_login => data}`. This information can be retrieved by the @appinstance object through a call similiar to this `@appinstance.system2_login`. This removes the requirement of using `@appinstance.logins `and looping through the returned hash if you are aware of the logins that Connect will be sending your application.

Each login is mapped as a login object associated to the `@appinstance` object. Every attribute associated to this object passed from Connect is available on this object as an attribute. At a minimum the below attributes will be available


|    Name     |                Description                 |
| ----------- | ------------------------------------------ |
| tenant_type | Login type such as "Zuora" or "Salesforce" |
| username    | The username                               |
| password    | The password                               |
| url         | Endpoint or URL                            |

#### Zuora logins
The Connect Gem has built-in integration with the Zuora gem and automatically creates a ZuoraLogin object for every Zuora login. This can be accessed by executing something similiar to the following:
```ruby
@appinstance.target_login.client.rest_call
```

### Admin authentication

#### Controller

Authentication is done through a before filter. Reference the above section on controller setup

#### View

`is_app_admin?` is a view helper that returns true if the user is an admin

### API Authentication

In order to allow direct access to the application without Connect for API calls the :authenticate_app_api_request before filter must be used in your controller and both authenticate_connect_app_request and persist_connect_app_session filters should be skipped to avoid collision.

When making an API call to your application the token associated to the `@appinstance` object must be passed in as the password in a basic auth header with the username being the users Connect username or in the access_token param

## Rails Console

By Default all queries executed from Rails Console will filter against schemas that are named “Public” and your current system $user. You can verify this by executing `ActiveRecord::Base.connection.schema_search_path` in rails console which should return “”$user", public"

The Connect Gem will create/use schemas tied to the TaskIds coming out of Connect. In Development mode this TaskId will default to 1. To query data out in development mode you would open up rails console and execute `ActiveRecord::Base.connection.schema_search_path = 1` before proceeding to subsequent queries

## Delayed Job

In order to use delayed job the configuration option “delayed_job” must be set to true for jobs to be picked up by your workers

### Installation
1. Set `config.delayed_job = true` in `config/initializers/connect.rb`
2. Add the following line to the connect.rb init file `Dir["#{Rails.root}/lib/workers/*.rb"].each {|file| require file }`
3. Add the following gems to your gem file
```ruby
gem "delayed_job"
gem "delayed_job_active_record"
gem "daemons"
gem "delayed_job_web" #Optional if a web interface is needed for job management
```
4. Run `rails generate delayed_job:active_record` in the terminal
5. Add `config.active_job.queue_adapter = :delayed_job` to `config/application.rb`

### Usage

#### Creating a Worker Class

Add a worker file based on the following template to lib/workers/worker.rb
```ruby
class Worker
  attr_accessor :schema
  def initialize(instance_id,var2)
    @instance_id = instance_id
    @var2 = var2
    @schema = ActiveRecord::Base.connection.schema_search_path
  end

  def perform()
    @appinstance = ZuoraConnect::AppInstance.find(@instance_id)
    @appinstance.new_session()
  end
end
```

#### Queueing Jobs

Jobs can be queued anywhere in the code base by using the following code `Delayed::Job.enqueue(Worker.new(@appinstance.id, var2))`. Note that instead of passing in the @appinstance object we always pass in the id. This must happen for schema segmentation to work correctly. This can be disregarded if your worker is not processing data specific to a users app instance.

Reference [here](https://github.com/collectiveidea/delayed_job) for more information on Running Jobs and creating workers

#### Starting the delayed job daemon

Run `bin/delayed_job -n 2 restart` in your terminal to start 2 processes that will pick up all queued jobs
