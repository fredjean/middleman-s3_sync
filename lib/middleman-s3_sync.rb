require 'middleman-core'
require 'middleman/s3_sync'

class S3SyncExtension < ::Middleman::Extension
  option :prefix, '', ''
  option :acl, 'public-read', 'Access restrictions for resources'
  option :bucket, '', 'The name of the bucket we are pushing to'
  option :region, 'us-east-1', 'The region of the bucket we are pushing to'
  option :aws_access_key_id, ENV['AWS_ACCESS_KEY_ID'], 'The AWS access key used to authenticate against AWS'
  option :aws_secret_access_key, ENV['AWS_SECRET_ACCESS_KEY'], 'The AWS secret access key'
  option :after_build, false, "Should we run the sync after the site is built"
  option :delete, true, 'Should we delete resources that are no longer present locally'
  option :prefer_gzip, true, 'Look for the compressed content'
  option :encryption, false, 'Should we use encryption at rest on the bucket'
  option :force, false, 'Should we force update the remote resources'
  option :reduced_redundancy_storage, false, 'Should we use the reduced redundancy storage option'
  option :path_style, true, 'Should we use path style to communicate with AWS'
  option :version_bucket, false, 'Should we version the bucket\'s content by default?'
  option :verbose, false, 'Should we be verbose...'

  def initialize(app, options_hash={}, &block)
    super

    root_path = ::Middleman::Application.root
    config_file_path = File.join(root_path, '.s3_sync')

    return unless File.exists?(config_file_path)
    io = File.open(config_file_path, 'r')

    config = YAML.load(io)

    options.aws_access_key_id = config["aws_access_key_id"] if config["aws_access_key_id"]
    options.aws_secret_access_key = config["aws_secret_access_key"] if config["aws_secret_access_key"]
  end
  alias :included :registered

  def after_build
    ::Middleman::S3Sync.sync if options.after_build
  end

  helpers do
    def default_caching_policy(policy = {})

    end

    def caching_policy(content_type, policy = {})

    end
  end

  protected
  def caching_policies
    @caching_policies ||= Map.new
  end

end

::Middleman::Extensions.register(:s3_sync, S3SyncExtension)

