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

      def step(name)
        ActiveSupport::Notifications.instrument('rack-profiler.step', step_name: name) do
          yield
        end
      end

      def render_dashboard
        dashboard = ::File.expand_path( '../../public/rack-profiler.html', ::File.dirname( __FILE__ ) )
        body      = ::File.open(dashboard, ::File::RDONLY)
        [200, { 'Content-Type' => 'text/html', 'Cache-Control' => 'public, max-age=86400' }, body]
      end

      def subscribe(name)
        (@subscriptions ||= []) << name
        @subscriptions.uniq!
      end

      def subscriptions
        @subscriptions || []
      end

      private
    end

    extend ClassMethods

    subscribe('sql.active_record')
    subscribe('rack-profiler.step')
    subscribe('render_template.action_view')
    subscribe('render_partial.action_view')
    subscribe('process_action.action_controller')

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
        [200, { 'Content-Type' => 'application/json' }, [{ events: nested_events, response: { status: status, headers: headers, body: body } }.to_json]]
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

    def nested_events
      events.sort_by { |evt| evt[:start] }.reduce([]) do |list, evt|
        nest_event(list, list, evt)
      end
    end

    private

    def subscribe_all_events
      self.class.subscriptions.each do |event|
        subscribe(event)
      end
    end

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
      if self.class.backtrace_filter.nil?
        backtrace
      else
        backtrace.select(&self.class.backtrace_filter)
      end
    end
  end
end
