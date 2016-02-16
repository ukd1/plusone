module Plusone
  class Counter
    def initialize(repo, issue_number = nil)
      @repo, @issue_number = repo, issue_number
    end

    def set_issue_number(issue_number)
      @issue_number = issue_number
    end

    def incr(user_id)
      $redis.sadd(redis_key, user_id)
    end

    def count
      $redis.scard(redis_key).to_i.to_s
    end

    def badge_signature
      Signature.get(redis_key)
    end

    def injest_signature
      Signature.get("injest/#{@repo}")
    end

    private def redis_key
      "p1:#{@repo}:#{@issue_number}"
    end
  end
end
