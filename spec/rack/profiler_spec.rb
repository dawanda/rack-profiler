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
      profiler = Rack::Profiler.new(nil) do |config|
        config.subscribe("bar")
      end
      trigger_dummy_event("bar")
      expect(profiler.events.last[:name]).to eq("bar")
    end

    it "executes the given block passing self" do
      block_arg = nil
      profiler = Rack::Profiler.new(nil) do |p|
        block_arg = p
      end
      expect(block_arg).to be(profiler)
    end

    it "sets the correct defaults" do
      expect(profiler.dashboard_path).to eq('/rack-profiler')
      expect(profiler.backtrace_filter).to be_nil
      expect(profiler.authorizator).to be_nil
      expect(profiler.subscriptions).to include(
        *Rack::Profiler::DEFAULT_SUBSCRIPTIONS
      )
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
      profiler.filter_backtrace do |line|
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

    it "accepts more than one subscription" do
      profiler.subscribe('baz', 'qux')
      trigger_dummy_event('baz')
      event = profiler.events.last
      expect(event[:name]).to eq('baz')
      trigger_dummy_event('qux')
      event = profiler.events.last
      expect(event[:name]).to eq('qux')
    end

    it "prevents duplicate subscriptions" do
      profiler.subscribe('baz')
      profiler.subscribe('baz')
      trigger_dummy_event('baz')
      expect(profiler.events.size).to eq(1)
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
        "PATH_INFO"         => "/",
        "QUERY_STRING"      => "",
        "REMOTE_HOST"       => "localhost",
        "REQUEST_METHOD"    => "GET",
        "REQUEST_URI"       => "http://localhost:3000/",
        "SCRIPT_NAME"       => "",
        "SERVER_NAME"       => "localhost",
        "SERVER_PORT"       => "3000",
        "SERVER_PROTOCOL"   => "HTTP/1.1",
        "HTTP_HOST"         => "localhost:3000",
        "rack.version"      => [1, 2],
        "rack.input"        => StringIO.new,
        "rack.errors"       => StringIO.new,
        "rack.multithread"  => true,
        "rack.multiprocess" => false,
        "rack.run_once"     => false,
        "rack.url_scheme"   => "http",
        "HTTP_VERSION"      => "HTTP/1.1",
        "REQUEST_PATH"      => "/"
      }
    end

    it "clears events" do
      profiler.events << 'xxx'
      profiler.call(env)
      expect(profiler.events).not_to include('xxx')
    end

    context "when the path is dashboard_path" do
      it "renders dashboard" do
        path = ::File.expand_path('../../public/rack-profiler.html',
                                     ::File.dirname( __FILE__ ) )
        status, header, body = profiler.call env.merge(
          "PATH_INFO"    => profiler.dashboard_path,
          "REQUEST_PATH" => profiler.dashboard_path
        )
        expect(body).to be_a(File)
        expect(body.path).to eq(path)
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

      context "when authorization is configured" do
        before do
          profiler.authorize { |env| env['rack-profiler-allowed'] }
        end

        it "returns the original response if the request is not authorized" do
          response = profiler.call(env_with_param)
          expect(response).to eq(
            [200, { 'X-My-Header' => 'foo' }, ['hello hello']]
          )
        end

        it "returns the profiler results if the request is authorized" do
          status, headers, body = profiler.call(
            env_with_param.merge('rack-profiler-allowed' => true)
          )
          parsed_body = JSON.parse(body.join)
          expect(parsed_body).to have_key('events')
        end
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

    it "returns whatever is returned by the block" do
      returned = Rack::Profiler.step("xxx") do
        "do stuff"
      end
      expect(returned).to eq("do stuff")
    end
  end
end
