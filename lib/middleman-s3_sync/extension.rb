require 'middleman-core'
require 'middleman/s3_sync'
require 'map'

module Middleman
  class S3SyncExtension < Extension
    # Options supported by the extension...
    option :prefix, nil, 'Path prefix of the resource we are looking for on the server.'
    option :http_prefix, nil, 'Path prefix of the resources'
    option :acl, 'public-read', 'ACL for the resources being pushed to S3'
    option :bucket, nil, 'The name of the bucket we are pushing to.'
    option :region, 'us-east-1', 'The name of the AWS region hosting the S3 bucket'
    option :aws_access_key_id, ENV['AWS_ACCESS_KEY_ID'] , 'The AWS access key id'
    option :aws_secret_access_key, ENV['AWS_SECRET_ACCESS_KEY'], 'The AWS secret access key'
    option :after_build, false, 'Whether to synchronize right after the build'
    option :build_dir, nil, 'Where the built site is stored'
    option :delete, true, 'Whether to delete resources that do not have a local equivalent'
    option :encryption, false, 'Whether to encrypt the content on the S3 bucket'
    option :force, false, 'Whether to push all current resources to S3'
    option :prefer_gzip, true, 'Whether to push the compressed version of the resource to S3'
    option :reduced_redundancy_storage, nil, 'Whether to use the reduced redundancy storage option'
    option :path_style, true, 'Whether to use path_style URLs to communiated with S3'
    option :version_bucket, false, 'Whether to enable versionning on the S3 bucket content'
    option :verbose, false, 'Whether to provide more verbose output'
    option :dry_run, false, 'Whether to perform a dry-run'
    option :index_document, nil, 'S3 custom index document path'
    option :error_document, nil, 'S3 custom error document path'

    def initialize(app, options_hash = {}, &block)
      super
      app.define_hook :after_s3_sync
      # Temporary workaround for 3.3 and 3.4.
      app.send :include, ClassMethods
    end

    def after_configuration
      read_config
      options.aws_access_key_id ||= ENV['AWS_ACCESS_KEY_ID']
      options.aws_secret_access_key ||= ENV['AWS_SECRET_ACCESS_KEY']
      options.bucket ||= ENV['AWS_BUCKET']
      options.http_prefix = app.http_prefix if app.respond_to? :http_prefix
      options.build_dir ||= app.build_dir if app.respond_to? :build_dir
      if options.prefix
        options.prefix = options.prefix.end_with?("/") ? options.prefix : options.prefix + "/"
      end
      ::Middleman::S3Sync.s3_sync_options = s3_sync_options
    end

    def after_build
      ::Middleman::S3Sync.sync() if options.after_build
    end

    def manipulate_resource_list(mm_resources)
      ::Middleman::S3Sync.mm_resources = mm_resources
    end

    def s3_sync_options
      options
    end

    # Read config options from an IO stream and set them on `self`. Defaults
    # to reading from the `.s3_sync` file in the MM project root if it exists.
    #
    # @param io [IO] an IO stream to read from
    # @return [void]
    def read_config(io = nil)
      unless io
        root_path = ::Middleman::Application.root
        config_file_path = File.join(root_path, ".s3_sync")

        # skip if config file does not exist
        return unless File.exists?(config_file_path)

        io = File.open(config_file_path, "r")
      end

      config = (YAML.load(io) || {}).symbolize_keys

      config.each do |key, value|
        options[key.to_sym] = value
      end
    end


    module ClassMethods
      def s3_sync_options
        ::Middleman::S3SyncExtension.s3_sync_options
      end

      def default_caching_policy(policy = {})
        ::Middleman::S3Sync.add_caching_policy(:default, policy)
      end

      def caching_policy(content_type, policy = {})
        ::Middleman::S3Sync.add_caching_policy(content_type, policy)
      end
    end
  end

  ::Middleman::Extensions.register(:s3_sync, S3SyncExtension)
end

