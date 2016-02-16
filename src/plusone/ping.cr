module Plusone
  module Ping
    def self.start_pinging_redis
      # Keep redis alive
      spawn do
        loop do
          $redis.ping
          sleep(1)
        end
      end
    end
  end
end
