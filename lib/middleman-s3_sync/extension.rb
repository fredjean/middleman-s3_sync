require 'middleman-core'

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
      :build_dir
    )
    end

    class << self
      def options
        @@options
      end

      def registered(app, options_hash = {}, &block)
        options = Options.new(options_hash)
        yield options if block_given?

        @@options = options

        app.send :include, Helpers

        app.after_configuration do |config|
          options.build_dir = build_dir
        end

        app.after_build do |builder|
          ::Middleman::S3Sync.sync if options.after_build
        end
      end

      alias :included :registered

      module Helpers
        def options
          ::Middleman::S3Sync.options
        end
      end
    end
  end
end
