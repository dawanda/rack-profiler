require "spec_helper"
require 'json'

def trigger_dummy_event(name, payload = {})
  ActiveSupport::Notifications.instrument(name, payload) do
    "do stuff"
  end
end

describe Rack::Profiler do
  let(:profiler) { Rack::Profiler.new(nil) }

  it "has a version number" do
    expect(Rack::Profiler::VERSION).not_to be_nil
  end

  describe :initialize do
    it "subscribes to all subscriptions" do
      config = Rack::Profiler::Configuration.new
      config.subscribe("bar")
      allow(Rack::Profiler).to receive(:config).and_return(config)

      profiler = Rack::Profiler.new(nil)
      trigger_dummy_event("bar")
      expect(profiler.events.last[:name]).to eq("bar")
    end
  end

  describe :subscribe do
    before do
      profiler.subscribe("foo")
    end

    it "subscribes to event populating the event list" do
      trigger_dummy_event("foo")
      event = profiler.events.last
      expect(event[:name]).to eq("foo")
    end

    it "populates event with the proper keys" do
      trigger_dummy_event("foo")
      event = profiler.events.last
      expect(event.keys).to include(:id, :name, :start, :finish, :duration, :payload, :backtrace)
    end

    it "adds the backtrace" do
      trigger_dummy_event("foo")
      event = profiler.events.last
      expect(event[:backtrace].any? do |line|
        line.include?("trigger_dummy_event")
      end).to be(true)
    end

    it "filters the backtrace if a filter was provided" do
      Rack::Profiler.config.filter_backtrace do |line|
        !line.include?("trigger_dummy_event")
      end
      trigger_dummy_event("foo")
      event = profiler.events.last
      expect(event[:backtrace].any? do |line|
        line.include?("trigger_dummy_event")
      end).to be(false)
      expect(event[:backtrace].any? do |line|
        line.include?(__FILE__)
      end).to be(true)
    end

    it "adds the payload" do
      trigger_dummy_event("foo", bar: "baz")
      event = profiler.events.last
      expect(event[:payload]).to eq(bar: "baz")
    end
  end

  describe :call do
    let(:app) do
      Proc.new { |env|
        Rack::Profiler.step 'foo' do
          [200, { 'X-My-Header' => 'foo' }, ['hello hello']]
        end
      }
    end

    let(:profiler) do
      Rack::Profiler.new(app)
    end

    let(:env) do
      {
        "PATH_INFO" => "/",
        "QUERY_STRING" => "",
        "REMOTE_HOST" => "localhost",
        "REQUEST_METHOD" => "GET",
        "REQUEST_URI" => "http://localhost:3000/",
        "SCRIPT_NAME" => "",
        "SERVER_NAME" => "localhost",
        "SERVER_PORT" => "3000",
        "SERVER_PROTOCOL" => "HTTP/1.1",
        "HTTP_HOST" => "localhost:3000",
        "rack.version" => [1, 2],
        "rack.input" => StringIO.new,
        "rack.errors" => StringIO.new,
        "rack.multithread" => true,
        "rack.multiprocess" => false,
        "rack.run_once" => false,
        "rack.url_scheme" => "http",
        "HTTP_VERSION" => "HTTP/1.1",
        "REQUEST_PATH" => "/"
      }
    end

    it "clears events" do
      profiler.events << 'xxx'
      profiler.call(env)
      expect(profiler.events).not_to include('xxx')
    end

    context "when the path is config.dashboard_path" do
      it "renders dashboard" do
        expect(profiler).to receive(:render_dashboard)
        profiler.call env.merge(
          "PATH_INFO"    => profiler.config.dashboard_path,
          "REQUEST_PATH" => profiler.config.dashboard_path
        )
      end
    end

    context "when the rack-profiler parameter is not present" do
      it "transparently returns the original response" do
        expect(profiler.call(env)).to eq(app.call(env))
      end
    end

    context "when the rack-profiler parameter is present" do
      let(:env_with_param) {
        env.merge('QUERY_STRING' => 'rack-profiler')
      }

      it "returns a JSON response" do
        status, headers, body = profiler.call(env_with_param)
        expect(headers).to match('Content-Type' => 'application/json')
        expect { JSON.parse(body.join) }.not_to raise_error
      end

      it "puts the original response in the JSON payload" do
        status, headers, body = profiler.call(env_with_param)
        parsed_body = JSON.parse(body.join)
        expect(parsed_body['response']).to eq(
          'status'  => 200,
          'headers' => { 'X-My-Header' => 'foo' },
          'body'    => 'hello hello'
        )
      end

      it "puts the received events in the JSON payload" do
        status, headers, body = profiler.call(env_with_param)
        parsed_body = JSON.parse(body.join)
        expect(
          parsed_body['events'].map { |e| e['name'] }
        ).to include('rack-profiler.total_time', 'rack-profiler.step')
      end
    end
  end

  describe ".step" do
    it "calls ActiveSupport::Notifications.instrument with the right args" do
      expect(ActiveSupport::Notifications).to receive(:instrument).with(
        "rack-profiler.step", { step_name: "xxx" })
      Rack::Profiler.step("xxx") do
        "do stuff"
      end
    end

    it "mixes data in the payload if provided" do
      expect(ActiveSupport::Notifications).to receive(:instrument).with(
        "rack-profiler.step", { step_name: "xxx", foo: "bar" })
      Rack::Profiler.step("xxx", foo: "bar") do
        "do stuff"
      end
    end
  end

  describe ".configure" do
    it "executes the given block passing the configuration object" do
      config_inside_block = nil
      Rack::Profiler.configure do |c|
        config_inside_block = c
      end
      expect(config_inside_block).to be(Rack::Profiler.config)
    end
  end

  describe ".config" do
    it "instantiates a Configuration object if there is none" do
      Rack::Profiler.send(:instance_variable_set, :@config, nil)
      expect(Rack::Profiler.config).to be_a(Rack::Profiler::Configuration)
    end
  end
end

describe Rack::Profiler::Configuration do
  let(:config) { Rack::Profiler::Configuration.new }

  it "has the correct defaults" do
    expect(config.dashboard_path).to eq('/rack-profiler')
    expect(config.backtrace_filter).to be_nil
    expect(config.subscriptions).to include(
      *Rack::Profiler::Configuration::DEFAULT_SUBSCRIPTIONS
    )
  end

  describe :subscribe do
    it "adds entries to subscriptions" do
      config.subscribe('bar')
      expect(config.subscriptions).to include('bar')
    end

    it "accepts more than one subscription" do
      config.subscribe('bar', 'baz')
      expect(config.subscriptions).to include('bar', 'baz')
    end

    it "does not add duplicates" do
      config.subscribe('bar', 'bar')
      expect(
        config.subscriptions.count { |s| s == 'bar' }
      ).to eq(1)
    end
  end

  describe :filter_backtrace do
    it "sets the backtrace_filter" do
      config.filter_backtrace do |line|
        line.include? 'foo'
      end
      filtered = ['foo', 'foobar', 'baz'].select(&config.backtrace_filter)
      expect(filtered).to eq(['foo', 'foobar'])
    end
  end
end
