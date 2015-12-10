# Rack::Profiler

[![Build Status](https://travis-ci.org/dawanda/rack-profiler.svg)](https://travis-ci.org/dawanda/rack-profiler) [![Code Climate](https://codeclimate.com/github/dawanda/rack-profiler/badges/gpa.svg)](https://codeclimate.com/github/dawanda/rack-profiler) [![Test Coverage](https://codeclimate.com/github/dawanda/rack-profiler/badges/coverage.svg)](https://codeclimate.com/github/dawanda/rack-profiler)
[![Gem Version](https://badge.fury.io/rb/rack-profiler.svg)](http://badge.fury.io/rb/rack-profiler)

Simple profiler for Rack applications (Sinatra, Ruby on Rails, or Grape for example).
It helps providing an answer to common questions like:

  - Where is time spent in requests to my app?
  - Which SQL queries are executed by `ActiveRecord`?
  - Which are the parts of my app's request flow that need optimization?

And more.

`Rack::Profiler` uses the [Active Support Instrumentation
API](http://guides.rubyonrails.org/active_support_instrumentation.html) and
subscribes by default to the following hooks:

  * [sql.active_record](http://guides.rubyonrails.org/active_support_instrumentation.html#sql-active-record)
  * [render_template.action_view](http://guides.rubyonrails.org/active_support_instrumentation.html#render_template.action_view)
  * [render_partial.action_view](http://guides.rubyonrails.org/active_support_instrumentation.html#render_partial.action_view)
  * [process_action.action_controller](http://guides.rubyonrails.org/active_support_instrumentation.html#process_action.action_controller)

`Rack::Profiler` also automatically subscribes to [Grape's](https://github.com/ruby-grape/grape) Active Support Instrumentation notifications
  * [endpoint_run.grape](https://github.com/ruby-grape/grape#performance-monitoring)
  * [endpoint_render.grape](https://github.com/ruby-grape/grape#performance-monitoring)
  * [endpoint_run_filters.grape](https://github.com/ruby-grape/grape#performance-monitoring)

On top of this, you can also define your own events, by wrapping your code with
the [`Rack::Profiler.step`](#custom-steps).

`Rack::Profiler` is easy to integrate in any Rack application and it produces a
JSON response with the results. It also exposes a simple web dashboard to directly
issue HTTP requests to your application and see the results of the profiling.

![Rack::Profiler Web Dashboard](http://i.imgur.com/tcUSYle.png?1)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rack-profiler'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install rack-profiler

### Rack/Sinatra/Grape

In your `config.ru` use the `Rack::Profiler` middleware at the beginning of your
middleware stack:

```ruby
require 'rack/profiler'
use Rack::Profiler
```

NOTE: you should not expose the profiler publicly in the production environment,
as it may contain sensitive information. Refer to the [`authorization
section`](#authorization) on how to protect it.

### Rails

You can add the `Rack::Profiler` middleware at the beginning of your `config.ru`
like in the Rack/Sinatra installation or insert it in the middlewares stack configuration
in your `config/environments/<env>.rb` files:

```ruby
YourApp.configure do |config|
  # ...

  config.middleware.insert 0, Rack::Profiler
end
```

NOTE: you should not expose the profiler publicly in the production environment,
as it may contain sensitive information. Refer to the [`authorization
section`](#authorization) for on to protect it.

## Configuration

You can configure `Rack::Profiler` passing a block to `use` (or
`middleware.insert` in Rails configuration). In the block you can subscribe to
more notifications and change some defaults:

```ruby
use Rack::Profiler do |profiler|
  # Subscribe to email delivery in a Rails app
  profiler.subscribe('deliver.action_mailer')

  # You can also exclude lines that are not interesting from the backtrace
  # For example, exclude gems from the backtrace:
  profiler.filter_backtrace { |line| !line.include? '/gems/' }
end
```

## Authorization

You typically *do not want to expose profiling publicly*, as it may contain
sensible information about your data and app. To protect your data, the easiest
option is to only enable the profiler in the development environment:

```ruby
if ENV['RACK_ENV'] == 'development'
  require 'rack/profiler'
  use Rack::Profiler
end
```

Sometimes though, you might want to run the profiler in the production
environment, in order to get results in a real setting (including caching and
optimizations). In this case, you can configure your custom authorization logic,
which can rely on the Rack env:

```ruby
use Rack::Profiler do |profiler|
  profiler.authorize do |env|
    # env is the Rack environment of the request. This block should return a
    # truthy value when the request is allowed to be profiled, falsy otherwise.
    env['rack-profiler-enabled'] == true
  end
end

# ...then in your app:
before do
  env['rack-profiler-enabled'] = true if current_user.admin?
end
```

## Usage

### Custom steps

By default `Rack::Profiler` will subscribe to `ActiveRecord` SQL queries,
`ActionView` rendering events (templates and partials), `ActionController`
actions and to steps you define in your code with:

```ruby
Rack::Profiler.step('your-step-name') do
  # Do stuff. The profiler will tell you how long it took to perform this step
end
```

### Web Dashboard

A graphical interface to profile your application pages/endpoints and display the
results is automatically mounted at this route:

    http://<your-app-url>/rack-profiler

Just select the HTTP verb, insert the relative path to your app and add some
optional parameters like POST/PUT data: `Rack::Profiler` automatically send
the request to your app with the `rack-profiler` param and display the
results in a nice graphical way.


### Raw JSON result

If you want to access the results of the profiling as raw JSON data, you can just
add the `rack-profiler` parameter (it can be null) to any HTTP request
to your app (GET, POST, PUT, PATCH, DELETE): `Rack::Profiler` will execute the
request and return a JSON response containing the results along with the
original response.

    http://<your-app-url>/<path>?rack-profiler

## Contributing

1. Fork it ( https://github.com/dawanda/rack-profiler/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
