module Plusone
  module Signature
    def self.get(key)
      OpenSSL::HMAC.hexdigest(:sha512, ENV["HMAC_SECRET"], key.to_s)
    end
  end
end
