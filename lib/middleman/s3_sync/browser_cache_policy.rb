module S3Sync
  class BrowserCachePolicy
    attr_accessor :policies

    def initialize(options)
      @policies = Map.from_hash(options)

    end
    def cache_control
      policy = []
      policy << "max-age=#{policies.max_age}" if policies.has_key?(:max_age)
      policy << "s-maxage=#{policies.s_maxage}" if policies.has_key?(:s_maxage)
      policy << "public" if policies.fetch(:public, false)
      policy << "private" if policies.fetch(:private, false)
      policy << "no-cache" if policies.fetch(:no_cache, false)
      policy << "no-store" if policies.fetch(:no_store, false)
      policy << "must-revalidate" if policies.fetch(:must_revalidate, false)
      policy << "proxy-revalidate" if policies.fetch(:proxy_revalidate, false)
      if policy.empty?
        nil
      else
        policy.join(", ")
      end
    end

    def to_s
      cache_control
    end

    def expires
      if expiration = policies.fetch(:expires, nil)
        CGI.rfc1123_date(expiration)
      end
    end
  end
end
