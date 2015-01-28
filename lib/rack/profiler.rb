require "rack"
require "rack/request"
require "rack/profiler/version"
require "active_support/notifications"

module Rack
  class Profiler

    attr_reader :events, :backtrace_filter, :subscriptions
    attr_accessor :dashboard_path

    DEFAULT_SUBSCRIPTIONS = ['sql.active_record',
                             'render_template.action_view',
                             'render_partial.action_view',
                             'process_action.action_controller',
                             'rack-profiler.total_time',
                             'rack-profiler.step']

    class DummyError < StandardError; end

    def self.step(name, payload = {})
      ActiveSupport::Notifications.instrument('rack-profiler.step', payload.merge(step_name: name)) do
        yield
      end
    end

    def initialize(app, &block)
      @events         = []
      @subscriptions  = []
      @dashboard_path = '/rack-profiler'
      @app            = app
      subscribe_to_default
      block.call(self) if block_given?
    end

    def call(env)
      @events = []
      req = Rack::Request.new(env)

      if req.path == dashboard_path
        render_dashboard
      elsif req.params.has_key?('rack-profiler')
        render_profiler_results(env)
      else
        @app.call(env)
      end
    end

    def subscribe(*events)
      events.each do |event_name|
        next if @subscriptions.include?(event_name)
        ActiveSupport::Notifications.subscribe(event_name) do |name, start, finish, id, payload|
          evt = {
            id:        id,
            name:      name,
            start:     start.to_f,
            finish:    finish.to_f,
            duration:  (finish - start) * 1000,
            payload:   payload,
            backtrace: filtered_backtrace(caller(1))
          }
          (@events ||= []) << evt
        end
        @subscriptions << event_name
      end
    end

    def filter_backtrace(&block)
      @backtrace_filter = block
    end

    private

    def render_profiler_results(env)
      status, headers, body = [nil, nil, nil]
      ActiveSupport::Notifications.instrument('rack-profiler.total_time') do
        status, headers, body = @app.call(env)
      end
      [ 200,
        { 'Content-Type' => 'application/json' },
        [ { events:   events.sort_by { |event| event[:start] },
            response: {
            status:  status,
            headers: headers,
            body:    stringify_body(body)
          }
        }.to_json ]
      ]
    end

    def render_dashboard
      dashboard = ::File.expand_path( '../../public/rack-profiler.html',
                                     ::File.dirname( __FILE__ ) )
      body      = ::File.open(dashboard, ::File::RDONLY)
      [200, { 'Content-Type' => 'text/html' }, body]
    end

    def subscribe_to_default
      DEFAULT_SUBSCRIPTIONS.each do |event|
        subscribe(event)
      end
    end

    def filtered_backtrace(backtrace)
      if backtrace_filter.nil?
        backtrace
      else
        backtrace.select(&backtrace_filter)
      end
    end

    def stringify_body(body)
      body.close if body.respond_to?(:close)
      str = ""
      body.each { |part| str << part }
      str
    end
  end
end
