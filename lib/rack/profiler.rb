require "rack/profiler/version"
require "active_support/notifications"

module Rack
  class Profiler
    class DummyError < StandardError; end

    module ClassMethods
      def configure(&block)
        instance_exec(self, &block)
      end

      def filter_backtrace(&block)
        @_backtrace_filter = block
      end

      def dashboard_path=(path)
        @_dashboard_path = path
      end

      def dashboard_path
        @_dashboard_path || '/rack-profiler'
      end

      def events
        @events ||= []
      end

      def nested_events
        events.sort_by { |evt| evt[:start] }.reduce([]) do |list, evt|
          nest_event(list, list, evt)
        end
      end

      def reset_events!
        @events = []
      end

      def step(name)
        ActiveSupport::Notifications.instrument('rack-profiler.step', step_name: name) do
          yield
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
          Profiler.events << evt
        end
      end

      def render_dashboard
        dashboard = ::File.expand_path( '../../public/rack-profiler.html', ::File.dirname( __FILE__ ) )
        body      = ::File.open(dashboard, ::File::RDONLY)
        [200, { 'Content-Type' => 'text/html', 'Cache-Control' => 'public, max-age=86400' }, body]
      end

      private

      def nest_event(list, children, evt)
        previous = children.last
        if previous && evt[:finish] <= previous[:finish]
          nest_event(list, previous[:children] ||= [], evt)
        else
          children << evt
        end
        list
      end

      def tap_backtrace
        begin
          raise DummyError.new
        rescue DummyError => e
          e.backtrace
        end
      end

      def filtered_backtrace(backtrace)
        if @_backtrace_filter.nil?
          backtrace
        else
          backtrace.select(&@_backtrace_filter)
        end
      end
    end

    extend ClassMethods

    subscribe('sql.active_record')
    subscribe('rack-profiler.step')

    def initialize(app)
      @app = app
    end

    def call(env)
      Profiler.reset_events!
      status, headers, body = [nil, nil, nil]
      req = Rack::Request.new(env)

      if req.path == Profiler.dashboard_path
        Profiler.render_dashboard
      elsif req.params.has_key?('rack-profiler')
        Profiler.step('total_time') do
          status, headers, body = @app.call(env)
        end
        [200, { 'Content-Type' => 'application/json' }, [{ events: Profiler.nested_events, response: { status: status, headers: headers, body: body } }.to_json]]
      else
        @status, @headers, @body = @app.call(env)
      end
    end
  end
end
