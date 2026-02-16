require 'spec_helper'
require 'middleman/s3_sync'

describe 'S3Sync CloudFront Integration' do
  let(:app) { double('middleman_app') }
  let(:s3_sync_options) do
    double(
      cloudfront_invalidate: true,
      cloudfront_distribution_id: 'E1234567890123',
      cloudfront_invalidate_all: false,
      cloudfront_invalidation_batch_size: 1000,
      aws_access_key_id: 'test_key',
      aws_secret_access_key: 'test_secret',
      aws_session_token: nil,
      dry_run: false,
      verbose: false,
      delete: true,
      bucket: 'test-bucket',
      after_s3_sync: nil
    )
  end

  before do
    # Reset cached app to avoid double leakage between tests
    Middleman::S3Sync.instance_variable_set(:@app, nil)
    
    # Mock sitemap for ensure_resource_list_updated! call
    sitemap = double('sitemap')
    allow(sitemap).to receive(:ensure_resource_list_updated!)
    allow(app).to receive(:respond_to?).with(:sitemap).and_return(true)
    allow(app).to receive(:sitemap).and_return(sitemap)
    
    allow(::Middleman::Application).to receive(:new).and_return(app)
    allow(Middleman::S3Sync).to receive(:s3_sync_options).and_return(s3_sync_options)
    allow(Middleman::S3Sync).to receive(:say_status)
    allow(Middleman::S3Sync).to receive(:work_to_be_done?).and_return(true)
    allow(Middleman::S3Sync).to receive(:update_bucket_versioning)
    allow(Middleman::S3Sync).to receive(:update_bucket_website)
    allow(Middleman::S3Sync).to receive(:ignore_resources)
    allow(Middleman::S3Sync).to receive(:create_resources)
    allow(Middleman::S3Sync).to receive(:update_resources)
    allow(Middleman::S3Sync).to receive(:delete_resources)
    allow(Middleman::S3Sync::CloudFront).to receive(:invalidate)
  end

  describe 'CloudFront invalidation integration' do
    it 'calls CloudFront invalidation after sync operations' do
      # Reset invalidation paths for this test
      Middleman::S3Sync.instance_variable_set(:@invalidation_paths, Set.new)
      
      expect(Middleman::S3Sync::CloudFront).to receive(:invalidate).with(
        [], # Initially empty, gets populated during resource operations
        s3_sync_options
      )

      Middleman::S3Sync.sync
    end

    it 'calls CloudFront invalidation with collected paths' do
      # Mock the methods to inject paths during sync
      allow(Middleman::S3Sync).to receive(:create_resources) do
        Middleman::S3Sync.add_invalidation_path('/updated/file.html')
      end
      allow(Middleman::S3Sync).to receive(:update_resources) do
        Middleman::S3Sync.add_invalidation_path('/new/file.css')
      end

      expect(Middleman::S3Sync::CloudFront).to receive(:invalidate) do |paths, options|
        expect(paths).to include('/updated/file.html')
        expect(paths).to include('/new/file.css')
        expect(options).to eq(s3_sync_options)
      end

      Middleman::S3Sync.sync
    end

    context 'when cloudfront_invalidate_all is true' do
      let(:s3_sync_options) do
        double(
          cloudfront_invalidate: true,
          cloudfront_distribution_id: 'E1234567890123',
          cloudfront_invalidate_all: true,
          bucket: 'test-bucket',
          after_s3_sync: nil
        )
      end

      it 'still calls CloudFront invalidation even when no work is needed' do
        allow(Middleman::S3Sync).to receive(:work_to_be_done?).and_return(false)
        
        expect(Middleman::S3Sync::CloudFront).to receive(:invalidate).with(
          [], s3_sync_options
        )

        Middleman::S3Sync.sync
      end
    end

    context 'when CloudFront invalidation is disabled' do
      let(:s3_sync_options) do
        double(
          cloudfront_invalidate: false,
          bucket: 'test-bucket',
          after_s3_sync: nil
        )
      end

      it 'does not call CloudFront invalidation' do
        expect(Middleman::S3Sync::CloudFront).not_to receive(:invalidate)

        Middleman::S3Sync.sync
      end
    end
  end

  describe 'sitemap population' do
    it 'calls ensure_resource_list_updated! before processing resources' do
      sitemap = double('sitemap')
      expect(sitemap).to receive(:ensure_resource_list_updated!)
      allow(sitemap).to receive(:respond_to?).with(:ensure_resource_list_updated!).and_return(true)
      allow(app).to receive(:sitemap).and_return(sitemap)
      
      Middleman::S3Sync.sync
    end
    
    it 'handles apps without sitemap gracefully' do
      Middleman::S3Sync.instance_variable_set(:@app, nil)
      
      app_without_sitemap = double('app_without_sitemap')
      allow(app_without_sitemap).to receive(:respond_to?).with(:sitemap).and_return(false)
      allow(::Middleman::Application).to receive(:new).and_return(app_without_sitemap)
      
      # Should not raise an error
      expect { Middleman::S3Sync.sync }.not_to raise_error
    end
  end

  describe 'path tracking during resource operations' do
    before do
      # Reset invalidation paths before each path tracking test
      Middleman::S3Sync.instance_variable_set(:@invalidation_paths, Set.new)
    end

    it 'adds paths to invalidation list when resources are processed' do
      # Test the add_invalidation_path method directly
      Middleman::S3Sync.add_invalidation_path('test/file.html')
      Middleman::S3Sync.add_invalidation_path('images/photo.jpg')
      
      expect(Middleman::S3Sync.invalidation_paths).to include('/test/file.html')
      expect(Middleman::S3Sync.invalidation_paths).to include('/images/photo.jpg')
    end

    it 'normalizes paths when adding to invalidation list' do
      Middleman::S3Sync.add_invalidation_path('no-leading-slash.html')
      
      expect(Middleman::S3Sync.invalidation_paths).to include('/no-leading-slash.html')
    end

    it 'does not add duplicate paths' do
      Middleman::S3Sync.add_invalidation_path('/same/path.html')
      Middleman::S3Sync.add_invalidation_path('/same/path.html')
      
      # Set automatically handles uniqueness - verify it contains exactly one occurrence
      expect(Middleman::S3Sync.invalidation_paths.to_a.count('/same/path.html')).to eq(1)
    end
  end

  describe 'orphan file discovery (scan_build_dir)' do
    let(:build_dir) { Dir.mktmpdir }
    
    after do
      FileUtils.remove_entry(build_dir) if File.directory?(build_dir)
    end

    before do
      # Reset state
      Middleman::S3Sync.instance_variable_set(:@s3_sync_resources, {})
      Middleman::S3Sync.instance_variable_set(:@bucket_files, {})
      
      allow(Middleman::S3Sync).to receive(:say_status)
      allow(Middleman::S3Sync).to receive(:build_dir).and_return(build_dir)
      allow(Middleman::S3Sync).to receive(:remote_resource_for_path).and_return(nil)
    end

    context 'when scan_build_dir is enabled' do
      let(:s3_sync_options) do
        double(
          scan_build_dir: true,
          build_dir: build_dir,
          bucket: 'test-bucket',
          prefix: nil,
          delete: false,
          verbose: false,
          ignore_paths: [],
          prefer_gzip: false,
          force: false,
          acl: 'public-read',
          after_s3_sync: nil
        )
      end

      it 'discovers files not in sitemap' do
        # Create orphan files in build directory
        FileUtils.mkdir_p(File.join(build_dir, 'images'))
        File.write(File.join(build_dir, 'orphan.txt'), 'orphan content')
        File.write(File.join(build_dir, 'images', 'optimized.webp'), 'image data')
        
        # Mock Resource creation to avoid S3 calls
        allow(Middleman::S3Sync::Resource).to receive(:new) do |resource, remote, path: nil|
          mock_resource = double('resource', status: :new, path: path)
          allow(mock_resource).to receive(:tap).and_yield(mock_resource).and_return(mock_resource)
          mock_resource
        end
        
        Middleman::S3Sync.send(:discover_orphan_files)
        
        resources = Middleman::S3Sync.send(:s3_sync_resources)
        expect(resources.keys).to include('orphan.txt')
        expect(resources.keys).to include('images/optimized.webp')
      end

      it 'skips files already in sitemap' do
        File.write(File.join(build_dir, 'existing.html'), 'content')
        
        # Pre-populate sitemap resource
        Middleman::S3Sync.send(:s3_sync_resources)['existing.html'] = double('resource')
        
        # Count how many times Resource.new is called
        call_count = 0
        allow(Middleman::S3Sync::Resource).to receive(:new) do |resource, remote, path: nil|
          call_count += 1
          mock_resource = double('resource', status: :new, path: path)
          allow(mock_resource).to receive(:tap).and_yield(mock_resource).and_return(mock_resource)
          mock_resource
        end
        
        Middleman::S3Sync.send(:discover_orphan_files)
        
        # Should not have created a new resource for existing.html
        expect(call_count).to eq(0)
      end

      it 'skips directories' do
        FileUtils.mkdir_p(File.join(build_dir, 'subdir', 'nested'))
        File.write(File.join(build_dir, 'subdir', 'file.txt'), 'content')
        
        created_paths = []
        allow(Middleman::S3Sync::Resource).to receive(:new) do |resource, remote, path: nil|
          created_paths << path
          mock_resource = double('resource', status: :new, path: path)
          allow(mock_resource).to receive(:tap).and_yield(mock_resource).and_return(mock_resource)
          mock_resource
        end
        
        Middleman::S3Sync.send(:discover_orphan_files)
        
        expect(created_paths).to include('subdir/file.txt')
        expect(created_paths).not_to include('subdir')
        expect(created_paths).not_to include('subdir/nested')
      end
    end

    context 'when scan_build_dir is disabled' do
      let(:s3_sync_options) do
        double(
          scan_build_dir: false,
          build_dir: build_dir,
          bucket: 'test-bucket',
          after_s3_sync: nil
        )
      end

      it 'does not scan for orphan files' do
        File.write(File.join(build_dir, 'orphan.txt'), 'content')
        
        expect(Middleman::S3Sync).not_to receive(:discover_orphan_files)
        
        # Call work_to_be_done? but mock the heavy parts
        allow(Middleman::S3Sync).to receive(:mm_resources).and_return([])
        allow(Middleman::S3Sync).to receive(:remote_only_paths).and_return([])
        allow(Middleman::S3Sync).to receive(:files_to_create).and_return([])
        allow(Middleman::S3Sync).to receive(:files_to_update).and_return([])
        allow(Middleman::S3Sync).to receive(:files_to_delete).and_return([])
        
        Middleman::S3Sync.send(:work_to_be_done?)
      end
    end
  end

  describe 'batch delete operations' do
    let(:bucket) { double('bucket') }
    let(:resource1) { double('resource1', path: 'file1.html', remote_path: 'file1.html') }
    let(:resource2) { double('resource2', path: 'file2.html', remote_path: 'file2.html') }
    let(:resource3) { double('resource3', path: 'file3.html', remote_path: 'file3.html') }

    before do
      # Remove the stub for delete_resources so we test the actual implementation
      allow(Middleman::S3Sync).to receive(:delete_resources).and_call_original
      allow(Middleman::S3Sync).to receive(:say_status)
      allow(Middleman::S3Sync).to receive(:bucket).and_return(bucket)
      allow(Middleman::S3Sync).to receive(:s3_sync_options).and_return(s3_sync_options)
      Middleman::S3Sync.instance_variable_set(:@invalidation_paths, Set.new)
      Middleman::S3Sync.instance_variable_set(:@categorized_resources, nil)
    end

    it 'uses batch delete_objects API instead of individual deletes' do
      allow(Middleman::S3Sync).to receive(:files_to_delete).and_return([resource1, resource2, resource3])
      
      expect(bucket).to receive(:delete_objects).with(
        delete: {
          objects: [
            { key: 'file1.html' },
            { key: 'file2.html' },
            { key: 'file3.html' }
          ]
        }
      )

      Middleman::S3Sync.send(:delete_resources)
    end

    it 'adds invalidation paths for all deleted resources' do
      allow(Middleman::S3Sync).to receive(:files_to_delete).and_return([resource1, resource2])
      allow(bucket).to receive(:delete_objects)

      Middleman::S3Sync.send(:delete_resources)

      expect(Middleman::S3Sync.invalidation_paths).to include('/file1.html')
      expect(Middleman::S3Sync.invalidation_paths).to include('/file2.html')
    end

    it 'does not call delete_objects during dry run' do
      dry_run_options = double(
        dry_run: true,
        delete: true,
        bucket: 'test-bucket',
        after_s3_sync: nil
      )
      allow(Middleman::S3Sync).to receive(:s3_sync_options).and_return(dry_run_options)
      allow(Middleman::S3Sync).to receive(:files_to_delete).and_return([resource1])

      expect(bucket).not_to receive(:delete_objects)

      Middleman::S3Sync.send(:delete_resources)
    end

    it 'does nothing when there are no files to delete' do
      allow(Middleman::S3Sync).to receive(:files_to_delete).and_return([])

      expect(bucket).not_to receive(:delete_objects)

      Middleman::S3Sync.send(:delete_resources)
    end
  end

  describe 'after_s3_sync callback' do
    before do
      Middleman::S3Sync.instance_variable_set(:@app, nil)
      
      sitemap = double('sitemap')
      allow(sitemap).to receive(:ensure_resource_list_updated!)
      allow(app).to receive(:respond_to?).with(:sitemap).and_return(true)
      allow(app).to receive(:sitemap).and_return(sitemap)
      
      allow(::Middleman::Application).to receive(:new).and_return(app)
      allow(Middleman::S3Sync).to receive(:say_status)
      allow(Middleman::S3Sync).to receive(:work_to_be_done?).and_return(true)
      allow(Middleman::S3Sync).to receive(:update_bucket_versioning)
      allow(Middleman::S3Sync).to receive(:update_bucket_website)
      allow(Middleman::S3Sync).to receive(:ignore_resources)
      allow(Middleman::S3Sync).to receive(:create_resources)
      allow(Middleman::S3Sync).to receive(:update_resources)
      allow(Middleman::S3Sync).to receive(:delete_resources)
      allow(Middleman::S3Sync::CloudFront).to receive(:invalidate)
    end

    context 'when after_s3_sync callback is provided' do
      it 'executes the callback after sync completes' do
        callback_executed = false
        callback_options = double(
          cloudfront_invalidate: false,
          bucket: 'test-bucket',
          after_s3_sync: -> { callback_executed = true }
        )
        allow(Middleman::S3Sync).to receive(:s3_sync_options).and_return(callback_options)
        allow(Middleman::S3Sync).to receive(:files_to_create).and_return([])
        allow(Middleman::S3Sync).to receive(:files_to_update).and_return([])
        allow(Middleman::S3Sync).to receive(:files_to_delete).and_return([])

        Middleman::S3Sync.sync

        expect(callback_executed).to be true
      end

      it 'passes sync results to the callback' do
        received_results = nil
        callback_options = double(
          cloudfront_invalidate: false,
          bucket: 'test-bucket',
          after_s3_sync: ->(results) { received_results = results }
        )
        allow(Middleman::S3Sync).to receive(:s3_sync_options).and_return(callback_options)
        allow(Middleman::S3Sync).to receive(:files_to_create).and_return(['file1.html'])
        allow(Middleman::S3Sync).to receive(:files_to_update).and_return(['file2.html', 'file3.html'])
        allow(Middleman::S3Sync).to receive(:files_to_delete).and_return([])

        Middleman::S3Sync.sync

        expect(received_results).to be_a(Hash)
        expect(received_results[:created]).to eq(1)
        expect(received_results[:updated]).to eq(2)
        expect(received_results[:deleted]).to eq(0)
      end

      it 'logs callback execution status' do
        callback_options = double(
          cloudfront_invalidate: false,
          bucket: 'test-bucket',
          after_s3_sync: -> { 'done' }
        )
        allow(Middleman::S3Sync).to receive(:s3_sync_options).and_return(callback_options)
        allow(Middleman::S3Sync).to receive(:files_to_create).and_return([])
        allow(Middleman::S3Sync).to receive(:files_to_update).and_return([])
        allow(Middleman::S3Sync).to receive(:files_to_delete).and_return([])

        expect(Middleman::S3Sync).to receive(:say_status).with('callback', /Running after_s3_sync/)
        expect(Middleman::S3Sync).to receive(:say_status).with('callback', /after_s3_sync completed/)

        Middleman::S3Sync.sync
      end

      it 'handles callback errors gracefully' do
        error_callback_options = double(
          cloudfront_invalidate: false,
          bucket: 'test-bucket',
          after_s3_sync: ->(_results) { raise 'Callback error!' }
        )
        allow(Middleman::S3Sync).to receive(:s3_sync_options).and_return(error_callback_options)
        allow(Middleman::S3Sync).to receive(:files_to_create).and_return([])
        allow(Middleman::S3Sync).to receive(:files_to_update).and_return([])
        allow(Middleman::S3Sync).to receive(:files_to_delete).and_return([])

        expect(Middleman::S3Sync).to receive(:say_status).with('error', /Callback error!/)
        expect { Middleman::S3Sync.sync }.not_to raise_error
      end
    end

    context 'when after_s3_sync callback is nil' do
      it 'does not attempt to execute a callback' do
        nil_callback_options = double(
          cloudfront_invalidate: false,
          bucket: 'test-bucket',
          after_s3_sync: nil
        )
        allow(Middleman::S3Sync).to receive(:s3_sync_options).and_return(nil_callback_options)

        # Should not log callback execution
        expect(Middleman::S3Sync).not_to receive(:say_status).with('callback', anything)

        Middleman::S3Sync.sync
      end
    end

    context 'when after_s3_sync callback is a method name' do
      it 'executes the method on the app' do
        method_executed = false
        allow(app).to receive(:my_callback) { method_executed = true }
        allow(app).to receive(:respond_to?).with(:my_callback).and_return(true)
        allow(app).to receive(:method).with(:my_callback).and_return(double(arity: 0))
        
        method_callback_options = double(
          cloudfront_invalidate: false,
          bucket: 'test-bucket',
          after_s3_sync: :my_callback
        )
        allow(Middleman::S3Sync).to receive(:s3_sync_options).and_return(method_callback_options)
        allow(Middleman::S3Sync).to receive(:files_to_create).and_return([])
        allow(Middleman::S3Sync).to receive(:files_to_update).and_return([])
        allow(Middleman::S3Sync).to receive(:files_to_delete).and_return([])

        Middleman::S3Sync.sync

        expect(method_executed).to be true
      end
    end
  end
end
