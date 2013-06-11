require 'middleman-core'
require 'map'

module Middleman
  module S3Sync
    class Options < Struct.new(
      :prefix,
      :bucket,
      :region,
      :aws_access_key_id,
      :aws_secret_access_key,
      :after_build,
      :delete,
      :existing_remote_file,
      :build_dir,
      :force,
      :prefer_gzip,
      :verbose
    )

      def add_caching_policy(content_type, options)
        caching_policies[content_type.to_s] = BrowserCachePolicy.new(options)
      end

      def caching_policy_for(content_type)
        caching_policies.fetch(content_type.to_s, caching_policies[:default])
      end

      def default_caching_policy
        caching_policies[:default]
      end

      def caching_policies
        @caching_policies ||= Map.new
      end

      def aws_access_key_id
        self[:aws_access_key_id] || ENV['AWS_ACCESS_KEY_ID']
      end

      def aws_secret_access_key
        self[:aws_secret_access_key] || ENV['AWS_SECRET_ACCESS_KEY']
      end

      def delete
        self[:delete].nil? ? true : self[:delete]
      end

      def after_build
        self[:after_build].nil? ? false : self[:after_build]
      end

      def prefer_gzip
        self[:prefer_gzip].nil? ? true : self[:prefer_gzip]
      end

      protected
      class BrowserCachePolicy
        attr_accessor :policies

        def initialize(options)
          @policies = Map.from_hash(options)
        end

        def cache_control
          policy = []
          policy << "max-age=#{policies.max_age}" if policies.has_key?(:max_age)
          policy << "s-maxage=#{s_maxage}" if policies.has_key?(:s_maxage)
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

        def expires
          if expiration = policies.fetch(:expires, nil)
            CGI.rfc1123_date(expiration)
          end
        end
      end
    end

    class << self
      def s3_sync_options
        @@options
      end

      def registered(app, options_hash = {}, &block)
        options = Options.new(options_hash)
        yield options if block_given?

        @@options = options

        app.send :include, Helpers

        app.after_configuration do |config|
          options.build_dir ||= build_dir
        end

        app.after_build do |builder|
          ::Middleman::S3Sync.sync if options.after_build
        end
      end

      alias :included :registered

      module Helpers
        def s3_sync_options
          ::Middleman::S3Sync.s3_sync_options
        end

        def default_caching_policy(policy = {})
          s3_sync_options.add_caching_policy(:default, policy)
        end

        def caching_policy(content_type, policy = {})
          s3_sync_options.add_caching_policy(content_type, policy)
        end
      end
    end
  end
end
