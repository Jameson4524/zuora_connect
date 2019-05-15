Rails.application.routes.draw do

  mount Connect::Engine => "/connect"
end
