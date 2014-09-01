require 'middleman-core/cli'

module Middleman
  module Cli
    class S3Sync < Thor
      include Thor::Actions

      check_unknown_options!

      namespace :s3_sync

      def self.exit_on_failure?
        true
      end

      desc "s3_sync", "Pushes the minimum set of files needed to S3"
      method_option :force, type: :boolean,
        desc: "Push all local files to the server",
        aliases: '-f'
      method_option :bucket, type: :string,
        desc: "Specify which bucket to use, overrides the configured bucket.",
        aliases: '-b'
      method_option :verbose, type: :boolean,
        desc: "Adds more verbosity...",
        aliases: '-v'

      def s3_sync
        shared_inst = ::Middleman::Application.server.inst
        bucket = shared_inst.s3_sync_options.bucket rescue nil
        unless bucket
          raise Thor::Error.new "You need to activate the s3_sync extension."
        end

        s3_sync_options = shared_inst.s3_sync_options

        # Override options based on what was passed on the command line...
        s3_sync_options.force = options[:force] if options[:force]
        s3_sync_options.bucket = options[:bucket] if options[:bucket]
        s3_sync_options.verbose = options[:verbose] if options[:verbose]

        ::Middleman::S3Sync.sync(s3_sync_options)
      end
    end
    Base.map('sync' => 's3_sync')
  end
end
