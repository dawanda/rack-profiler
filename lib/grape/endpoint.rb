module Grape
  class Endpoint
    def as_json(options = nil)
      body.to_hash.as_json(options)
    end
  end
end
