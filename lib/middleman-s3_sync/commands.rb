require 'middleman-core/cli'

module Middleman
  module Cli
    class S3Sync < Thor::Group
      include Thor::Actions

      check_unknown_options!

      namespace :s3_sync

      def self.exit_on_failure?
        true
      end

      class_option :force, type: :boolean,
        desc: "Push all local files to the server",
        aliases: '-f'
      class_option :bucket, type: :string,
        desc: "Specify which bucket to use, overrides the configured bucket.",
        aliases: '-b'
      class_option :verbose, type: :boolean,
        desc: "Adds more verbosity...",
        aliases: '-v'
      class_option :dry_run, type: :boolean,
        desc: "Performs a dry run of the sync",
        aliases: '-n'

      def s3_sync
        ::Middleman::S3Sync.app = ::Middleman::Application.server.inst

        s3_sync_options = ::Middleman::S3Sync.s3_sync_options

        bucket = s3_sync_options.bucket rescue nil

        unless bucket
          raise Thor::Error.new "You need to activate the s3_sync extension and at least provide the bucket name."
        end


        #s3_sync_options = shared_inst.s3_sync_options

        # Override options based on what was passed on the command line...
        s3_sync_options.force = options[:force] if options[:force]
        s3_sync_options.bucket = options[:bucket] if options[:bucket]
        s3_sync_options.verbose = options[:verbose] if options[:verbose]
        s3_sync_options.dry_run = options[:dry_run] if options[:dry_run]

        ::Middleman::S3Sync.sync()
      end
    end

    Base.register(Middleman::Cli::S3Sync, 's3_sync', 's3_sync [options]', "Deploys a middleman site to a S3 bucket")

    Base.map("sync" => "s3_sync")
  end
end
