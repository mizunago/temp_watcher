#!/home/nagonago/.rbenv/versions/2.7.3/bin/ruby

APP_HOME = __dir__
load "#{APP_HOME}/app.rb"
set :run, false

Rack::Handler::CGI.run Sinatra::Application
