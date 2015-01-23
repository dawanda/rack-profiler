require 'spec_helper'

describe Rack::Profiler do
  before(:each) do
    Rack::Profiler.reset_events!
  end

  it 'has a version number' do
    expect(Rack::Profiler::VERSION).not_to be nil
  end

  describe ".events" do
    it "is an array" do
      expect(Rack::Profiler.events).to be_a(Array)
    end
  end

  describe ".nested_events" do
    it "returns events properly nested" do
      evt1 = { start: 1, finish: 10 }
      evt2 = { start: 2, finish: 3 }
      evt3 = { start: 4, finish: 8 }
      evt4 = { start: 5, finish: 8 }
      evt5 = { start: 9, finish: 10 }
      evts = [evt1, evt2, evt3, evt4, evt5]
      evts.each { |evt| Rack::Profiler.events << evt }
      nested = Rack::Profiler.nested_events
      expect(nested.first).to be(evt1)
      expect(evt1[:children].first).to be(evt2)
      expect(evt1[:children][1]).to be(evt3)
      expect(evt3[:children].first).to be(evt4)
      expect(evt1[:children].last).to be(evt5)
    end
  end

  describe ".subscribe" do
    def trigger_dummy_event(name, payload = {})
      ActiveSupport::Notifications.instrument(name, payload) do
        "do stuff"
      end
    end

    before do
      Rack::Profiler.subscribe('foo')
    end

    it "subscribe to event populating the event list" do
      trigger_dummy_event('foo')
      event = Rack::Profiler.events.last
      expect(event[:name]).to eq('foo')
    end

    it "populate event with the proper keys" do
      trigger_dummy_event('foo')
      event = Rack::Profiler.events.last
      expect(event.keys).to include(:id, :name, :start, :finish, :duration, :payload, :backtrace)
    end

    it "adds the backtrace" do
      trigger_dummy_event('foo')
      event = Rack::Profiler.events.last
      expect(event[:backtrace].any? do |line|
        line.include?("trigger_dummy_event")
      end).to be(true)
    end

    it "filters the backtrace if a filter was provided" do
      Rack::Profiler.filter_backtrace do |line|
        !line.include?("trigger_dummy_event")
      end
      trigger_dummy_event('foo')
      event = Rack::Profiler.events.last
      expect(event[:backtrace].any? do |line|
        line.include?("trigger_dummy_event")
      end).to be(false)
      expect(event[:backtrace].any? do |line|
        line.include?(__FILE__)
      end).to be(true)
    end

    it "adds the payload" do
      trigger_dummy_event('foo', bar: 'baz')
      event = Rack::Profiler.events.last
      expect(event[:payload]).to eq(bar: 'baz')
    end
  end

  describe ".step" do
    it "calls ActiveSupport::Notifications.instrument with the right arguments" do
      expect(ActiveSupport::Notifications).to receive(:instrument).with(
        'rack-profiler.step', { step_name: 'xxx' })
      Rack::Profiler.step('xxx') do
        "do stuff"
      end
    end
  end
end
