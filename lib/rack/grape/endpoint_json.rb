module Rack
  module Grape
    module EndpointJson
      def as_json(options = nil)
        return {}.as_json(options) if body.nil? || !body.respond_to?(:as_json)
        body.as_json(options)
      end
    end
  end
end
