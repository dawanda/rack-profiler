require "rack/profiler/version"
require "active_support/notifications"

module Rack
  class Profiler
    class DummyError < StandardError; end

    module ClassMethods
      attr_reader :backtrace_filter

      def configure(&block)
        instance_exec(self, &block)
      end

      def filter_backtrace(&block)
        @backtrace_filter = block
      end

      def dashboard_path=(path)
        @dashboard_path = path
      end

      def dashboard_path
        @dashboard_path || '/rack-profiler'
      end

      def step(name, payload = {})
        ActiveSupport::Notifications.instrument('rack-profiler.step', payload.merge(step_name: name)) do
          yield
        end
      end

      def render_dashboard
        dashboard = ::File.expand_path( '../../public/rack-profiler.html', ::File.dirname( __FILE__ ) )
        body      = ::File.open(dashboard, ::File::RDONLY)
        [200, { 'Content-Type' => 'text/html' }, body]
      end

      def subscribe(name)
        (@subscriptions ||= []) << name
        @subscriptions.uniq!
      end

      def subscriptions
        @subscriptions || []
      end
    end

    extend ClassMethods

    # Subscribe to interesting events
    subscribe('sql.active_record')
    subscribe('render_template.action_view')
    subscribe('render_partial.action_view')
    subscribe('process_action.action_controller')
    subscribe('rack-profiler.step')

    attr_reader :events

    def initialize(app)
      subscribe_all_events
      @app = app
    end

    def call(env)
      @events = []
      status, headers, body = [nil, nil, nil]
      req = Rack::Request.new(env)

      if req.path == Profiler.dashboard_path
        Profiler.render_dashboard
      elsif req.params.has_key?('rack-profiler')
        Profiler.step('total_time') do
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

    private

    def subscribe_all_events
      self.class.subscriptions.each do |event|
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
      if self.class.backtrace_filter.nil?
        backtrace
      else
        backtrace.select(&self.class.backtrace_filter)
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
