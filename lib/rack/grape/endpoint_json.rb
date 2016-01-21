module Rack
  module Grape
    module EndpointJson
      def as_json(options = nil)
        return {}.as_json(options) if body.nil?
        body.to_hash.as_json(options)
      end
    end
  end
end
