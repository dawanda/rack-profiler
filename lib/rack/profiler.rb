require "rack"
require "rack/request"
require "rack/profiler/version"
require "active_support/notifications"

module Rack
  class Profiler
    class DummyError < StandardError; end

    module ClassMethods
      def configure(&block)
        block.call(config)
      end

      def config
        @config ||= Configuration.new
      end

      def step(name, payload = {})
        ActiveSupport::Notifications.instrument('rack-profiler.step', payload.merge(step_name: name)) do
          yield
        end
      end
    end

    class Configuration
      attr_reader :subscriptions, :backtrace_filter
      attr_accessor :dashboard_path

      DEFAULT_SUBSCRIPTIONS = ['sql.active_record',
                               'render_template.action_view',
                               'render_partial.action_view',
                               'process_action.action_controller',
                               'rack-profiler.total_time',
                               'rack-profiler.step']

      def initialize
        @subscriptions  = DEFAULT_SUBSCRIPTIONS.clone
        @dashboard_path = '/rack-profiler'
      end

      def subscribe(*names)
        names.each { |name| @subscriptions << name }
        @subscriptions.uniq!
      end

      def filter_backtrace(&block)
        @backtrace_filter = block
      end
    end

    extend ClassMethods

    attr_reader :events

    def initialize(app)
      subscribe_to_all
      @events = []
      @app    = app
    end

    def call(env)
      @events = []
      status, headers, body = [nil, nil, nil]
      req = Rack::Request.new(env)

      if req.path == config.dashboard_path
        render_dashboard
      elsif req.params.has_key?('rack-profiler')
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
      else
        @status, @headers, @body = @app.call(env)
      end
    end

    def subscribe(event_name)
      ActiveSupport::Notifications.subscribe(event_name) do |name, start, finish, id, payload|
        backtrace = filtered_backtrace(tap_backtrace)
        evt = {
          id:        id,
          name:      name,
          start:     start.to_f,
          finish:    finish.to_f,
          duration:  (finish - start) * 1000,
          payload:   payload,
          backtrace: backtrace
        }
        (@events ||= []) << evt
      end
    end

    def config
      self.class.config
    end

    private

    def render_dashboard
      dashboard = ::File.expand_path( '../../public/rack-profiler.html', ::File.dirname( __FILE__ ) )
      body      = ::File.open(dashboard, ::File::RDONLY)
      [200, { 'Content-Type' => 'text/html' }, body]
    end

    def subscribe_to_all
      # Subscribe to interesting events
      config.subscriptions.each do |event|
        subscribe(event)
      end
    end

    def tap_backtrace
      begin
        raise DummyError.new
      rescue DummyError => e
        e.backtrace
      end
    end

    def filtered_backtrace(backtrace)
      if config.backtrace_filter.nil?
        backtrace
      else
        backtrace.select(&config.backtrace_filter)
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
