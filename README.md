# Rack::Profiler

[![Build Status](https://travis-ci.org/dawanda/rack-profiler.svg)](https://travis-ci.org/dawanda/rack-profiler)

Simple profiler for Rack applications (Sinatra and Ruby on Rails for example).
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

On top of this, you can also define your own events, by wrapping your code with
the [`Rack::Profiler.step`](#custom-steps).

`Rack::Profiler` is easy to integrate in any Rack application and it produces a
JSON response with the results. It also exposes a simple web dashboard to directly
issue HTTP requests to your application and see the results of the profiling.

![Rack::Profiler Web Dashboard](http://i.imgur.com/tcUSYle.png)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rack-profiler'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install rack-profiler

### Rack/Sinatra

In your `config.ru` use the `Rack::Profiler` middleware at the beginning of your
middleware stack:

```ruby
require 'rack/profiler'
use Rack::Profiler
```

### Rails

You can add the `Rack::Profiler` middleware at the beginning of your `config.ru`
like in the Rack/Sinatra installation or insert it in the middlewares stack configuration
in the `application.rb`:

```ruby
module YourApp
  class Application < Rails::Application

    # ...

    config.middleware.insert_before Rack::Runtime, Rack::Profiler

  end
end
```

## Configuration

You can configure `Rack::Profiler` to subscribe to more notifications:

```ruby
Rack::Profiler.configure do |config|
  # Subscribe to email delivery in a Rails app
  config.subscribe('deliver.action_mailer')
end
```

You can also specify a backtrace filter to exclude lines that are not
interesting:

```ruby
Rack::Profiler.configure do |config|
  # Exclude gems from the backtrace
  config.filter_backtrace { |line| !line.include? '/gems/' }
end
```

You can put these configurations in your `config.ru` for a Rack/Sinatra application
or in an initializer `config/rack_profiler.rb` for Rails apps.

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
