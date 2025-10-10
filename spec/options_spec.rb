require 'spec_helper'

describe Middleman::S3Sync::Options do
  let(:options) { described_class.new }

  describe 'option accessors' do
    it 'provides accessors for all defined options' do
      described_class::OPTIONS.each do |option_name|
        expect(options).to respond_to(option_name)
        expect(options).to respond_to("#{option_name}=")
      end
    end
  end

  describe 'AWS credentials options' do
    it 'supports aws_access_key_id' do
      options.aws_access_key_id = 'test_key'
      expect(options.aws_access_key_id).to eq('test_key')
    end

    it 'supports aws_secret_access_key' do
      options.aws_secret_access_key = 'test_secret'
      expect(options.aws_secret_access_key).to eq('test_secret')
    end

    it 'supports aws_session_token' do
      options.aws_session_token = 'test_token'
      expect(options.aws_session_token).to eq('test_token')
    end

    it 'falls back to ENV for aws_access_key_id' do
      ENV['AWS_ACCESS_KEY_ID'] = 'env_key'
      expect(options.aws_access_key_id).to eq('env_key')
    ensure
      ENV.delete('AWS_ACCESS_KEY_ID')
    end

    it 'falls back to ENV for aws_secret_access_key' do
      ENV['AWS_SECRET_ACCESS_KEY'] = 'env_secret'
      expect(options.aws_secret_access_key).to eq('env_secret')
    ensure
      ENV.delete('AWS_SECRET_ACCESS_KEY')
    end
  end

  describe 'CloudFront options' do
    it 'supports cloudfront_distribution_id' do
      options.cloudfront_distribution_id = 'E1234567890123'
      expect(options.cloudfront_distribution_id).to eq('E1234567890123')
    end

    it 'supports cloudfront_invalidate' do
      options.cloudfront_invalidate = true
      expect(options.cloudfront_invalidate).to be true
    end

    it 'supports cloudfront_invalidate_all' do
      options.cloudfront_invalidate_all = true
      expect(options.cloudfront_invalidate_all).to be true
    end

    it 'supports cloudfront_invalidation_batch_size' do
      options.cloudfront_invalidation_batch_size = 500
      expect(options.cloudfront_invalidation_batch_size).to eq(500)
    end

    it 'supports cloudfront_invalidation_max_retries' do
      options.cloudfront_invalidation_max_retries = 10
      expect(options.cloudfront_invalidation_max_retries).to eq(10)
    end

    it 'supports cloudfront_invalidation_batch_delay' do
      options.cloudfront_invalidation_batch_delay = 5
      expect(options.cloudfront_invalidation_batch_delay).to eq(5)
    end

    it 'supports cloudfront_wait' do
      options.cloudfront_wait = true
      expect(options.cloudfront_wait).to be true
    end
  end

  describe 'S3 options' do
    it 'supports bucket' do
      options.bucket = 'my-bucket'
      expect(options.bucket).to eq('my-bucket')
    end

    it 'supports region' do
      options.region = 'us-west-2'
      expect(options.region).to eq('us-west-2')
    end

    it 'supports endpoint' do
      options.endpoint = 'https://s3-compatible.example.com'
      expect(options.endpoint).to eq('https://s3-compatible.example.com')
    end

    it 'supports prefix' do
      options.prefix = 'my-prefix'
      expect(options.prefix).to eq('my-prefix/')
    end

    it 'supports path_style' do
      options.path_style = false
      expect(options.path_style).to be false
    end

    it 'defaults path_style to true' do
      expect(options.path_style).to be true
    end

    it 'supports encryption' do
      options.encryption = true
      expect(options.encryption).to be true
    end

    it 'defaults encryption to false' do
      expect(options.encryption).to be false
    end

    it 'supports reduced_redundancy_storage' do
      options.reduced_redundancy_storage = true
      expect(options.reduced_redundancy_storage).to be true
    end
  end

  describe 'ACL options' do
    it 'supports acl' do
      options.acl = 'private'
      expect(options.acl).to eq('private')
    end

    it 'defaults acl to public-read' do
      expect(options.acl).to eq('public-read')
    end

    it 'supports acl_enabled?' do
      expect(options.acl_enabled?).to be true
    end

    context 'when acl is disabled' do
      it 'returns false for acl_enabled? when set to empty string' do
        options.acl = ''
        expect(options.acl_enabled?).to be false
      end

      it 'returns false for acl_enabled? when set to nil' do
        options.acl = nil
        expect(options.acl_enabled?).to be false
      end

      it 'returns false for acl_enabled? when set to false' do
        options.acl = false
        expect(options.acl_enabled?).to be false
      end
    end
  end

  describe 'sync behavior options' do
    it 'supports delete' do
      options.delete = false
      expect(options.delete).to be false
    end

    it 'defaults delete to true' do
      expect(options.delete).to be true
    end

    it 'supports force' do
      options.force = true
      expect(options.force).to be true
    end

    it 'supports prefer_gzip' do
      options.prefer_gzip = false
      expect(options.prefer_gzip).to be false
    end

    it 'defaults prefer_gzip to true' do
      expect(options.prefer_gzip).to be true
    end

    it 'supports verbose' do
      options.verbose = true
      expect(options.verbose).to be true
    end

    it 'supports dry_run' do
      options.dry_run = true
      expect(options.dry_run).to be true
    end

    it 'supports version_bucket' do
      options.version_bucket = true
      expect(options.version_bucket).to be true
    end

    it 'defaults version_bucket to false' do
      expect(options.version_bucket).to be false
    end
  end

  describe 'build options' do
    it 'supports build_dir' do
      options.build_dir = 'dist'
      expect(options.build_dir).to eq('dist')
    end

    it 'supports after_build' do
      options.after_build = true
      expect(options.after_build).to be true
    end

    it 'defaults after_build to false' do
      expect(options.after_build).to be false
    end
  end

  describe 'content options' do
    it 'supports content_types' do
      content_types = { '.webp' => 'image/webp' }
      options.content_types = content_types
      expect(options.content_types).to eq(content_types)
    end

    it 'supports ignore_paths' do
      ignore_paths = [/\.bak$/, 'temp/']
      options.ignore_paths = ignore_paths
      expect(options.ignore_paths).to eq(ignore_paths)
    end

    it 'defaults ignore_paths to empty array' do
      expect(options.ignore_paths).to eq([])
    end
  end

  describe 'website options' do
    it 'supports index_document' do
      options.index_document = 'index.html'
      expect(options.index_document).to eq('index.html')
    end

    it 'supports error_document' do
      options.error_document = '404.html'
      expect(options.error_document).to eq('404.html')
    end
  end

  describe 'option consistency' do
    it 'includes all options from extension in OPTIONS constant' do
      # These are the options defined in the extension
      extension_options = [
        :prefix, :http_prefix, :acl, :bucket, :endpoint, :region,
        :aws_access_key_id, :aws_secret_access_key, :aws_session_token,
        :after_build, :build_dir, :delete, :encryption, :force,
        :prefer_gzip, :reduced_redundancy_storage, :path_style,
        :version_bucket, :verbose, :dry_run, :index_document,
        :error_document, :content_types, :ignore_paths,
        :cloudfront_distribution_id, :cloudfront_invalidate,
        :cloudfront_invalidate_all, :cloudfront_invalidation_batch_size,
        :cloudfront_invalidation_max_retries, :cloudfront_invalidation_batch_delay,
        :cloudfront_wait
      ]

      extension_options.each do |option_name|
        expect(described_class::OPTIONS).to include(option_name),
          "Expected OPTIONS to include :#{option_name}"
      end
    end
  end
end
