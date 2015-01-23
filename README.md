# Rack::Profiler

Simple profiler for Rack applications

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rack-profiler'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install rack-profiler

## Usage

In your `config.ru` use the `Rack::Profiler` middleware at the beginning of your
middleware stack:

```ruby
require 'rack/profiler'
use Rack::Profiler
```

By default `Rack::Profiler` will subscribe to `ActiveRecord` SQL queries and to
steps you define in your code with:

```ruby
Rack::Profiler.step('your-step-name') do
  # Do stuff. The profiler will tell you how long it took to perform this step
end
```

You can also subscribe to more notifications:

```ruby
Rack::Profiler.configure do |profiler|
  # Subscribe to template rendering in a Rails app
  profiler.subscribe('render_template.action_view')
end
```

You can also specify a backtrace filter to exclude lines that are not
interesting:

```ruby
Rack::Profiler.configure do |profiler|
  # Exclude gems from the backtrace
  profiler.filter_backtrace { |line| !line.include? '/gems/' }
end
```

## Contributing

1. Fork it ( https://github.com/[my-github-username]/rack-profiler/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
