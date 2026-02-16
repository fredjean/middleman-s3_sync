require 'spec_helper'

describe 'AWS SDK Parameter Validation' do
  let(:options) { Middleman::S3Sync::Options.new }
  let(:s3_client) { instance_double(Aws::S3::Client) }
  let(:s3_resource) { instance_double(Aws::S3::Resource) }
  let(:bucket) { instance_double(Aws::S3::Bucket) }
  let(:s3_object) { instance_double(Aws::S3::Object) }

  before do
    Middleman::S3Sync.s3_sync_options = options
    options.build_dir = "build"
    options.bucket = "test-bucket"
    options.acl = "public-read"
    options.index_document = "index.html"
    options.error_document = "404.html"
    options.version_bucket = true

    allow(Aws::S3::Client).to receive(:new).and_return(s3_client)
    allow(Aws::S3::Resource).to receive(:new).and_return(s3_resource)
    allow(s3_resource).to receive(:bucket).and_return(bucket)
    allow(bucket).to receive(:exists?).and_return(true)
    allow(bucket).to receive(:object).and_return(s3_object)
    allow(s3_object).to receive(:put).and_return(true)

    # Allow Middleman::S3Sync to use our mocked client/bucket
    allow(Middleman::S3Sync).to receive(:s3_client).and_return(s3_client)
    allow(Middleman::S3Sync).to receive(:bucket).and_return(bucket)
    allow(Middleman::S3Sync).to receive(:say_status)
  end

  describe 'put_bucket_website parameters' do
    it 'uses symbol keys for index_document and error_document' do
      expect(s3_client).to receive(:put_bucket_website) do |params|
        expect(params[:bucket]).to eq("test-bucket")
        expect(params[:website_configuration]).to have_key(:index_document)
        expect(params[:website_configuration]).to have_key(:error_document)
        
        # Verify the nested structure uses symbols, not strings
        expect(params[:website_configuration][:index_document]).to have_key(:suffix)
        expect(params[:website_configuration][:error_document]).to have_key(:key)
        
        # Verify the values are correct
        expect(params[:website_configuration][:index_document][:suffix]).to eq("index.html")
        expect(params[:website_configuration][:error_document][:key]).to eq("404.html")
      end

      Middleman::S3Sync.send(:update_bucket_website)
    end

    context 'when only index_document is set' do
      before do
        options.error_document = nil
      end

      it 'only includes index_document in website configuration' do
        expect(s3_client).to receive(:put_bucket_website) do |params|
          expect(params[:website_configuration]).to have_key(:index_document)
          expect(params[:website_configuration]).not_to have_key(:error_document)
        end

        Middleman::S3Sync.send(:update_bucket_website)
      end
    end

    context 'when neither document is set' do
      before do
        options.index_document = nil
        options.error_document = nil
      end

      it 'does not call put_bucket_website' do
        expect(s3_client).not_to receive(:put_bucket_website)

        Middleman::S3Sync.send(:update_bucket_website)
      end
    end

    context 'when only error_document is set' do
      before do
        options.index_document = nil
      end

      it 'raises an error because S3 requires index_document if error_document is specified' do
        expect {
          Middleman::S3Sync.send(:update_bucket_website)
        }.to raise_error('S3 requires `index_document` if `error_document` is specified')
      end
    end

    context 'when routing_rules are set' do
      before do
        options.routing_rules = [
          {
            condition: { key_prefix_equals: 'docs/' },
            redirect: { replace_key_prefix_with: 'documents/' }
          },
          {
            condition: { http_error_code_returned_equals: '404' },
            redirect: { host_name: 'example.com', replace_key_with: 'error.html' }
          }
        ]
      end

      it 'includes routing_rules in website configuration' do
        expect(s3_client).to receive(:put_bucket_website) do |params|
          expect(params[:website_configuration]).to have_key(:routing_rules)
          rules = params[:website_configuration][:routing_rules]
          expect(rules).to be_an(Array)
          expect(rules.length).to eq(2)
          
          # First rule
          expect(rules[0][:condition][:key_prefix_equals]).to eq('docs/')
          expect(rules[0][:redirect][:replace_key_prefix_with]).to eq('documents/')
          
          # Second rule
          expect(rules[1][:condition][:http_error_code_returned_equals]).to eq('404')
          expect(rules[1][:redirect][:host_name]).to eq('example.com')
          expect(rules[1][:redirect][:replace_key_with]).to eq('error.html')
        end

        Middleman::S3Sync.send(:update_bucket_website)
      end
    end

    context 'when routing_rules are set without index_document' do
      before do
        options.index_document = nil
        options.error_document = nil
        options.routing_rules = [
          {
            condition: { key_prefix_equals: 'old/' },
            redirect: { replace_key_prefix_with: 'new/' }
          }
        ]
      end

      it 'raises an error because S3 requires index_document if routing_rules are specified' do
        expect {
          Middleman::S3Sync.send(:update_bucket_website)
        }.to raise_error('S3 requires `index_document` if `routing_rules` are specified')
      end
    end
  end

  describe 'put_bucket_versioning parameters' do
    it 'uses correct parameter structure' do
      expect(s3_client).to receive(:put_bucket_versioning) do |params|
        expect(params[:bucket]).to eq("test-bucket")
        expect(params[:versioning_configuration]).to be_a(Hash)
        expect(params[:versioning_configuration][:status]).to eq("Enabled")
      end

      Middleman::S3Sync.send(:update_bucket_versioning)
    end

    context 'when version_bucket is false' do
      before do
        options.version_bucket = false
      end

      it 'does not call put_bucket_versioning' do
        expect(s3_client).not_to receive(:put_bucket_versioning)

        Middleman::S3Sync.send(:update_bucket_versioning)
      end
    end
  end

  describe 'S3 object upload parameters' do
    let(:mm_resource) do
      double(
        destination_path: 'test/file.html',
        content_type: 'text/html'
      )
    end

    let(:resource) { Middleman::S3Sync::Resource.new(mm_resource, nil) }

    before do
      allow(File).to receive(:exist?).with('build/test/file.html').and_return(true)
      allow(File).to receive(:exist?).with('build/test/file.html.gz').and_return(false)
      allow(File).to receive(:read).with('build/test/file.html').and_return('test content')
      allow(File).to receive(:directory?).with('build/test/file.html').and_return(false)
      # Stub File.open to return a StringIO for streaming upload tests
      allow(File).to receive(:open).with('build/test/file.html', 'rb').and_yield(StringIO.new('test content'))
      allow(s3_object).to receive(:head).and_return(nil)
      options.dry_run = false
    end

    it 'uses correct metadata key format' do
      expect(s3_object).to receive(:put) do |upload_options|
        # Verify body is a readable IO object (for streaming)
        expect(upload_options[:body]).to respond_to(:read)
        expect(upload_options[:body].read).to eq('test content')
        expect(upload_options[:content_type]).to eq('text/html')
        expect(upload_options[:acl]).to eq('public-read')
        
        # Verify metadata uses correct key format (suffix only, not full header name)
        expect(upload_options[:metadata]).to be_a(Hash)
        expect(upload_options[:metadata]).to have_key('content-md5')
        expect(upload_options[:metadata]).not_to have_key('x-amz-meta-content-md5')
        
        # Verify metadata value is the MD5 hash
        expected_md5 = Digest::MD5.hexdigest('test content')
        expect(upload_options[:metadata]['content-md5']).to eq(expected_md5)
      end

      resource.upload!
    end

    context 'when ACL is set to empty string (for buckets with ACLs disabled)' do
      before do
        options.acl = ''
      end

      it 'does not include acl parameter in upload' do
        expect(s3_object).to receive(:put) do |upload_options|
          expect(upload_options).not_to have_key(:acl)
          expect(upload_options[:body]).to respond_to(:read)
          expect(upload_options[:content_type]).to eq('text/html')
        end

        resource.upload!
      end
    end

    context 'when ACL is set to nil (for buckets with ACLs disabled)' do
      before do
        options.acl = nil
      end

      it 'does not include acl parameter in upload' do
        expect(s3_object).to receive(:put) do |upload_options|
          expect(upload_options).not_to have_key(:acl)
          expect(upload_options[:body]).to respond_to(:read)
          expect(upload_options[:content_type]).to eq('text/html')
        end

        resource.upload!
      end
    end

    context 'when bucket does not support ACLs (auto-detection)' do
      before do
        # ACL is enabled by default
        expect(options.acl).to eq('public-read')
      end

      it 'automatically retries without ACL when AccessControlListNotSupported error occurs' do
        call_count = 0
        # Use a reusable StringIO that can be rewound
        file_io = StringIO.new('test content')
        allow(File).to receive(:open).with('build/test/file.html', 'rb').and_yield(file_io)
        
        expect(s3_object).to receive(:put).twice do |upload_options|
          call_count += 1
          if call_count == 1
            # First call should include ACL
            expect(upload_options[:acl]).to eq('public-read')
            raise Aws::S3::Errors::AccessControlListNotSupported.new(nil, 'The bucket does not allow ACLs')
          else
            # Second call should not include ACL
            expect(upload_options).not_to have_key(:acl)
            expect(upload_options[:body]).to respond_to(:read)
            expect(upload_options[:content_type]).to eq('text/html')
          end
        end

        # Should automatically disable ACLs after the error
        resource.upload!
        expect(options.acl_enabled?).to be false
      end

      it 'permanently disables ACLs after detecting bucket does not support them' do
        call_count = 0
        allow(s3_object).to receive(:put) do |upload_options|
          call_count += 1
          if call_count == 1
            expect(upload_options[:acl]).to eq('public-read')
            raise Aws::S3::Errors::AccessControlListNotSupported.new(nil, 'The bucket does not allow ACLs')
          else
            # Subsequent calls should succeed without ACL
            expect(upload_options).not_to have_key(:acl)
            true
          end
        end
        
        resource.upload!
        expect(options.acl_enabled?).to be false
        
        # Verify ACLs stay disabled for future uploads
        resource.upload!
        expect(call_count).to eq(3) # First attempt, retry, and third upload
      end
    end

    context 'when gzip is enabled' do
      before do
        options.prefer_gzip = true
        allow(File).to receive(:exist?).with('build/test/file.html.gz').and_return(true)
        allow(File).to receive(:read).with('build/test/file.html.gz').and_return('gzipped content')
        allow(File).to receive(:exist?).with('build/test/file.html').and_return(true)
        allow(File).to receive(:read).with('build/test/file.html').and_return('original content')
        allow(File).to receive(:open).with('build/test/file.html.gz', 'rb').and_yield(StringIO.new('gzipped content'))
        
        # Mock the HEAD response to avoid calling it during redirect?
        head_response = double(
          metadata: {},
          etag: '"abc123"',
          content_encoding: nil,
          cache_control: nil,
          website_redirect_location: nil
        )
        allow(s3_object).to receive(:head).and_return(head_response)
        resource.instance_variable_set(:@full_s3_resource, head_response)
      end

      it 'includes content_encoding parameter' do
        expect(s3_object).to receive(:put) do |upload_options|
          expect(upload_options[:content_encoding]).to eq('gzip')
        end

        resource.upload!
      end
    end

    context 'when reduced redundancy storage is enabled' do
      before do
        options.reduced_redundancy_storage = true
      end

      it 'includes storage_class parameter' do
        expect(s3_object).to receive(:put) do |upload_options|
          expect(upload_options[:storage_class]).to eq('REDUCED_REDUNDANCY')
        end

        resource.upload!
      end
    end

    context 'when encryption is enabled' do
      before do
        options.encryption = true
      end

      it 'includes server_side_encryption parameter' do
        expect(s3_object).to receive(:put) do |upload_options|
          expect(upload_options[:server_side_encryption]).to eq('AES256')
        end

        resource.upload!
      end
    end

    context 'when resource has a redirect' do
      let(:mm_resource) do
        double(
          destination_path: 'redirect/file.html',
          content_type: 'text/html',
          redirect?: true,
          target_url: 'https://example.com/new-location'
        )
      end

      before do
        allow(File).to receive(:exist?).with('build/redirect/file.html').and_return(true)
        allow(File).to receive(:exist?).with('build/redirect/file.html.gz').and_return(false)
        allow(File).to receive(:read).with('build/redirect/file.html').and_return('redirect content')
        allow(File).to receive(:open).with('build/redirect/file.html', 'rb').and_yield(StringIO.new('redirect content'))
        allow(File).to receive(:directory?).with('build/redirect/file.html').and_return(false)
        allow(s3_object).to receive(:head).and_return(nil)
        allow(resource).to receive(:redirect?).and_return(true)
        allow(resource).to receive(:redirect_url).and_return('https://example.com/new-location')
      end

      it 'includes website_redirect_location parameter' do
        expect(s3_object).to receive(:put) do |upload_options|
          expect(upload_options[:website_redirect_location]).to eq('https://example.com/new-location')
        end

        resource.upload!
      end
    end
  end

  describe 'S3 object metadata retrieval' do
    let(:mm_resource) do
      double(
        destination_path: 'test/file.html',
        content_type: 'text/html'
      )
    end

    let(:resource) { Middleman::S3Sync::Resource.new(mm_resource, nil) }
    let(:head_response) do
      double(
        metadata: { 'content-md5' => 'abc123def456' },
        etag: '"def456abc123"',
        content_encoding: nil,
        cache_control: nil,
        website_redirect_location: nil
      )
    end

    before do
      allow(File).to receive(:exist?).with('build/test/file.html').and_return(true)
      allow(File).to receive(:read).with('build/test/file.html').and_return('test content')
      allow(File).to receive(:directory?).with('build/test/file.html').and_return(false)
      allow(s3_object).to receive(:head).and_return(head_response)
      resource.instance_variable_set(:@full_s3_resource, head_response)
    end

    it 'reads metadata using correct key format' do
      expect(resource.remote_content_md5).to eq('abc123def456')
    end

    it 'does not try to read metadata with old header format' do
      # Ensure it's not looking for the full header name
      expect(head_response.metadata).not_to receive(:[]).with('x-amz-meta-content-md5')
      
      resource.remote_content_md5
    end
  end

  describe 'to_h method for legacy compatibility' do
    let(:mm_resource) do
      double(
        destination_path: 'test/file.html',
        content_type: 'text/html'
      )
    end

    let(:resource) { Middleman::S3Sync::Resource.new(mm_resource, nil) }

    before do
      allow(File).to receive(:exist?).with('build/test/file.html').and_return(true)
      allow(File).to receive(:exist?).with('build/test/file.html.gz').and_return(false)
      allow(File).to receive(:read).with('build/test/file.html').and_return('test content')
      allow(File).to receive(:directory?).with('build/test/file.html').and_return(false)
      allow(s3_object).to receive(:head).and_return(nil)
    end

    it 'returns attributes with correct key formats' do
      attributes = resource.to_h

      expect(attributes[:key]).to eq('test/file.html')
      expect(attributes[:acl]).to eq('public-read')
      expect(attributes[:content_type]).to eq('text/html')
      expect(attributes['content-md5']).to be_a(String)
      expect(attributes).not_to have_key('x-amz-meta-content-md5')
    end

    context 'when ACL is set to empty string' do
      before do
        options.acl = ''
      end

      it 'does not include acl in attributes' do
        attributes = resource.to_h

        expect(attributes).not_to have_key(:acl)
        expect(attributes[:key]).to eq('test/file.html')
        expect(attributes[:content_type]).to eq('text/html')
      end
    end

    context 'when ACL is set to nil' do
      before do
        options.acl = nil
      end

      it 'does not include acl in attributes' do
        attributes = resource.to_h

        expect(attributes).not_to have_key(:acl)
        expect(attributes[:key]).to eq('test/file.html')
        expect(attributes[:content_type]).to eq('text/html')
      end
    end

    context 'when resource has a redirect' do
      let(:mm_resource) do
        double(
          destination_path: 'redirect/file.html',
          content_type: 'text/html',
          redirect?: true,
          target_url: 'https://example.com/new-location'
        )
      end

      before do
        allow(File).to receive(:exist?).with('build/redirect/file.html').and_return(true)
        allow(File).to receive(:exist?).with('build/redirect/file.html.gz').and_return(false)
        allow(File).to receive(:read).with('build/redirect/file.html').and_return('redirect content')
        allow(File).to receive(:directory?).with('build/redirect/file.html').and_return(false)
        allow(s3_object).to receive(:head).and_return(nil)
        allow(resource).to receive(:redirect?).and_return(true)
        allow(resource).to receive(:redirect_url).and_return('https://example.com/new-location')
      end

      it 'includes redirect with correct key format' do
        attributes = resource.to_h

        expect(attributes['website-redirect-location']).to eq('https://example.com/new-location')
        expect(attributes).not_to have_key('x-amz-website-redirect-location')
      end
    end
  end

  describe 'Regression tests for Fog-style parameter issues' do
    # These tests validate that we've fixed the old Fog-style parameter formatting
    # and demonstrate what would fail if we reverted to the old style

    it 'does not use string keys for website configuration (old Fog style)' do
      # This would fail if we reverted to the old format:
      # opts[:index_document] = { "suffix" => s3_sync_options.index_document }
      
      expect(s3_client).to receive(:put_bucket_website) do |params|
        config = params[:website_configuration]
        
        # Ensure we're not using string keys (old Fog style)
        expect(config[:index_document]).not_to have_key("suffix")
        expect(config[:error_document]).not_to have_key("key")
        
        # Ensure we ARE using symbol keys (correct AWS SDK style)
        expect(config[:index_document]).to have_key(:suffix)
        expect(config[:error_document]).to have_key(:key)
      end

      Middleman::S3Sync.send(:update_bucket_website)
    end

    it 'does not use full header names in metadata (old style)' do
      mm_resource = double(
        destination_path: 'test/file.html',
        content_type: 'text/html'
      )
      resource = Middleman::S3Sync::Resource.new(mm_resource, nil)
      
      allow(File).to receive(:exist?).with('build/test/file.html').and_return(true)
      allow(File).to receive(:exist?).with('build/test/file.html.gz').and_return(false)
      allow(File).to receive(:read).with('build/test/file.html').and_return('test content')
      allow(File).to receive(:open).with('build/test/file.html', 'rb').and_yield(StringIO.new('test content'))
      allow(File).to receive(:directory?).with('build/test/file.html').and_return(false)
      allow(s3_object).to receive(:head).and_return(nil)
      options.dry_run = false

      expect(s3_object).to receive(:put) do |upload_options|
        # Ensure we're not using the old full header format
        expect(upload_options[:metadata]).not_to have_key('x-amz-meta-content-md5')
        
        # Ensure we ARE using the correct suffix-only format
        expect(upload_options[:metadata]).to have_key('content-md5')
      end

      resource.upload!
    end

    it 'validates that old constants are no longer used' do
      # This test ensures the old constants were removed/changed
      # If they still existed, this would be a sign we didn't clean up properly
      
      mm_resource = double(
        destination_path: 'test/file.html',
        content_type: 'text/html'
      )
      resource = Middleman::S3Sync::Resource.new(mm_resource, nil)
      
      allow(File).to receive(:exist?).with('build/test/file.html').and_return(true)
      allow(File).to receive(:exist?).with('build/test/file.html.gz').and_return(false)
      allow(File).to receive(:read).with('build/test/file.html').and_return('test content')
      allow(File).to receive(:directory?).with('build/test/file.html').and_return(false)
      allow(s3_object).to receive(:head).and_return(nil)
      allow(resource).to receive(:redirect?).and_return(true)
      allow(resource).to receive(:redirect_url).and_return('https://example.com/redirect')

      attributes = resource.to_h
      
      # Validate that the old constant values are not used
      expect(attributes).not_to have_key('x-amz-meta-content-md5')
      expect(attributes).not_to have_key('x-amz-website-redirect-location')
      
      # Validate that the correct formats are used
      expect(attributes).to have_key('content-md5')
      expect(attributes).to have_key('website-redirect-location')
    end
  end
end
