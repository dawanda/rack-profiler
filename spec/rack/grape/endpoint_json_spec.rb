require "json"
require "spec_helper"
require "grape"
require "grape_entity"
require "rack/test"
require "rack/profiler"

describe Rack::Grape::EndpointJson do
  include Rack::Test::Methods
  subject { Class.new(Grape::API) }
  let(:sample_hash) { { ping: :pong } }

  def app
    subject
  end

  describe "#as_json" do
    before do
      subject.use Rack::Profiler
    end

    it "working with String" do
      subject.get "/ping" do
        "pong"
      end
      get "/ping?rack-profiler"
      expect(JSON.parse(last_response.body)["response"]["body"]).to eql("pong")
    end

    it "working with NULL" do
      subject.get "/ping" do
        nil
      end
      get "/ping?rack-profiler"
      expect(JSON.parse(last_response.body)["response"]["body"]).to eql("")
    end

    it "working with #present" do
      entity_mock = Object.new
      allow(entity_mock).to receive(:represent).and_return(sample_hash.to_json)

      subject.get "/ping" do
        present Object.new, with: entity_mock
      end
      get "/ping?rack-profiler"
      expect(JSON.parse(last_response.body)["response"]["body"]).to eql(sample_hash.to_json)
    end

    it "working with Grape::Entity" do
      entity = Class.new(Grape::Entity) { expose :ping }

      subject.get "/ping" do
        entity.represent({ ping: :pong }).to_json
      end
      get "/ping?rack-profiler"
      expect(JSON.parse(last_response.body)["response"]["body"]).to eql(sample_hash.to_json)
    end
  end
end
