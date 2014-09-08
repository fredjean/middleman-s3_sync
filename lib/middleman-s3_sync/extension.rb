require 'middleman-core'
require 'map'

module Middleman
  module S3Sync
    class << self
      attr_accessor :options

      def registered(app, options_hash = {}, &block)
        options = Options.new
        yield options if block_given?

        @options = options

        app.send :include, Helpers

        app.define_hook :after_s3_sync

        app.after_configuration do |config|

          # Define the after_build step after during configuration so
          # that it's pushed to the end of the callback chain
          app.after_build do |builder|
            ::Middleman::S3Sync.sync(options) if options.after_build
          end

          options.build_dir ||= build_dir
        end
      end
      alias :included :registered

      def s3_sync_options
        @options
      end

      def s3_sync_options=(options)
        @options = options
      end

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
