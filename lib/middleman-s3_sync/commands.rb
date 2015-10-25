require 'middleman-cli'

module Middleman
  module Cli

    class S3Sync < Thor::Group
      include Thor::Actions

      check_unknown_options!

      namespace :s3_sync

      def self.exit_on_failure?
        true
      end

      class_option :environment,
                   aliases: '-e',
                   type: :string,
                   default: ENV['MM_ENV'] || ENV['RACK_ENV'] || 'production',
                   desc: 'The environment to deploy.'

      class_option :build,
                   type: :boolean,
                   aliases: '-B',
                   desc: 'Run `middleman build` before the sync step'

      class_option :force,
                   aliases: '-f',
                   type: :boolean,
                   desc: 'Push all local files to the server.'

      class_option :aws_access_key_id,
                   aliases: '-k',
                   type: :string,
                   desc: 'Specify aws_access_key_id, and overrides the configured value.'

      class_option :aws_secret_access_key,
                   aliases: '-s',
                   type: :string,
                   desc: 'Specify aws_secret_access_key, and overrides the configured value.'

      class_option :bucket,
                   aliases: '-b',
                   type: :string,
                   desc: 'Specify which bucket to use, overrides the configured bucket.'

      class_option :prefix,
                   aliases: '-p',
                   type: :string,
                   desc: 'Specify which prefix to use, overrides the configured prefix.'

      class_option :verbose,
                   aliases: '-v',
                   type: :boolean,
                   desc: 'Enables verbose log output.'

      class_option :dry_run,
                   aliases: '-n',
                   type: :boolean,
                   desc: 'Performs a dry run of the sync.'

      class_option :instrument,
                   aliases: '-i',
                   type: :string,
                   desc: 'Print instrument messages.'

      def s3_sync
        env = options[:environment].to_s.to_sym
        verbose = options[:verbose] ? 0 : 1
        instrument = options[:instrument]

        ::Middleman::S3Sync.app = ::Middleman::Application.new do
          config[:mode] = :build
          config[:environment] = env
          ::Middleman::Logger.singleton(verbose, instrument)
        end

        build(options)

        s3_sync_options = ::Middleman::S3Sync.s3_sync_options

        bucket = s3_sync_options.bucket rescue nil

        unless bucket
          raise Thor::Error.new 'You must provide the bucket name.'
        end

        # Override options based on what was passed on the command line...
        s3_sync_options.force = options[:force] if options[:force]
        s3_sync_options.aws_access_key_id = options[:aws_access_key_id] if options[:aws_access_key_id]
        s3_sync_options.aws_secret_access_key = options[:aws_secret_access_key] if options[:aws_secret_access_key]
        s3_sync_options.bucket = options[:bucket] if options[:bucket]
        s3_sync_options.verbose = options[:verbose] if options[:verbose]
        if options[:prefix]
          s3_sync_options.prefix  = options[:prefix] if options[:prefix]
          s3_sync_options.prefix = s3_sync_options.prefix.end_with?('/') ? s3_sync_options.prefix : s3_sync_options.prefix + '/'
        end
        s3_sync_options.dry_run = options[:dry_run] if options[:dry_run]

        ::Middleman::S3Sync.sync()
      end

      def build(options = {})
        if options[:build]
          run("middleman build -e #{options[:environment]}") || exit(1)
        end
      end
    end

    # Add to CLI
    Base.register(Middleman::Cli::S3Sync, 's3_sync', 's3_sync [options]', 'Synchronizes a middleman site to an AWS S3 bucket')

    # Alias "sync" to "s3_sync"
    Base.map('sync' => 's3_sync')
  end
end
