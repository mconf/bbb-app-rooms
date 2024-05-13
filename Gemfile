# frozen_string_literal: true

source 'http://rubygems.org'
git_source(:github) do |repo_name|
  repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?('/')
  "https://github.com/#{repo_name}.git"
end

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '~> 6.1.4'
# Include sqlite as the default database
gem 'sqlite3', '~> 1.3'
# Include postgres as another database option
gem 'pg', '~> 1.0'
# Use Puma as the app server
gem 'puma', '~> 3.12'
# Use SCSS for stylesheets
gem 'sass-rails', '~> 5.0'
# Use Terser as compressor for JavaScript assets
gem 'terser', '~> 1.1'
# See https://github.com/rails/execjs#readme for more supported runtimes
# gem 'mini_racer', platforms: :ruby

# Use CoffeeScript for .coffee assets and views
gem 'coffee-rails', '~> 5.0'
# Turbolinks makes navigating your web application faster. Read more: https://github.com/turbolinks/turbolinks
gem 'turbolinks', '~> 5'
# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'jbuilder', '~> 2.5'
# Use Redis adapter to run Action Cable in production
gem 'redis'
# gem 'redis', '~> 4.0'
# Use ActiveModel has_secure_password
# gem 'bcrypt', '~> 3.1.7'

# Use ActiveStorage variant
# gem 'mini_magick', '~> 4.8'

# Use Capistrano for deployment
# gem 'capistrano-rails', group: :development

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', '>= 1.1.0', require: false

gem 'rails_admin', '~> 2.0'

# Return texts I18n in .js
gem 'i18n-js', '~> 3.9'

gem 'awesome_print', require: 'ap'

group :development, :test do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
  gem 'dotenv-rails'
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'rspec'
  gem 'rspec_junit_formatter'
  gem 'rspec-rails', '~> 4.0.0'
  gem 'rubocop', '~> 0.79.0', require: false
  gem 'rubocop-rails', '~> 2.4.0', require: false
  gem 'shoulda-matchers', '~> 4.0'
end

group :development do
  # Access an interactive console on exception pages or by calling 'console' anywhere in the code.
  gem 'listen', '>= 3.0.5', '< 3.2'
  gem 'web-console', '>= 3.3.0'
  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  gem 'spring'
  gem 'spring-watcher-listen', '~> 2.0.0'
end

group :test do
  # Adds support for Capybara system testing and selenium driver
  gem 'capybara', '>= 2.15', '< 4.0'
  gem 'selenium-webdriver'
  # Easy installation and use of chromedriver to run system tests with Chrome
  # gem 'chromedriver-helper'
  gem 'webdrivers'
end

group :production do
  gem 'prometheus_exporter'
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data'

# Base
gem 'json'
gem 'bootstrap', '~> 5.3'
gem 'font-awesome-rails'
gem 'jquery-fileupload-rails'
gem 'jquery-rails'
gem 'jquery-ui-rails'
gem 'faraday'
gem 'repost', '~> 0.4.2'

# BigBlueButton API
gem 'bigbluebutton-api-ruby', git: 'https://github.com/mconf/bigbluebutton-api-ruby.git', tag: 'v1.9.0-mconf'

# AWS S3 API (to access Spaces API)
gem 'aws-sdk-s3', '~> 1'

# Authentication
gem 'rest-client'
gem 'omniauth', '~> 2.1.2'
gem 'omniauth-oauth2', '~> 1.8.0'
gem 'omniauth-rails_csrf_protection', '~> 1.0.1'
gem 'omniauth-bbbltibroker', git: 'https://github.com/bigbluebutton/omniauth-bbbltibroker.git', tag: '0.1.4'
gem 'omniauth-brightspace', git: 'https://github.com/mconf/omniauth-brightspace.git'

# Logging
gem 'lograge'
gem "logstash-event"

# Use the browser's timezone
# Using this fork mostly because of these changes:
# https://github.com/mconf/browser-timezone-rails/commit/5bcc66fe8585ce6504e271aaec46dc77f9afa14f
# https://github.com/mconf/browser-timezone-rails/commit/0f112459d8577ac9c5de354ffe5a97056587b2fb
# https://github.com/mconf/browser-timezone-rails/commit/2f98ada4c005ff82aba2a40c2851c097fd06175f
gem 'browser-timezone-rails', git: 'https://github.com/mconf/browser-timezone-rails.git'

# Pagination
gem 'kaminari'

# Friendly URL
gem 'friendly_id', '~> 5.4.0'

# Other
gem 'browser'

# For queues
gem 'resque', require: 'resque/server'
gem 'resque-scheduler', require: 'resque/scheduler/server'
gem 'active_scheduler'

# Asynchronous partial loading with AJAX
gem 'render_async', '~> 2.1'

# Select2
gem "select2-rails"
