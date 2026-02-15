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
      bucket: 'test-bucket'
    )
  end

  before do
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
          bucket: 'test-bucket'
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
          bucket: 'test-bucket'
        )
      end

      it 'does not call CloudFront invalidation' do
        expect(Middleman::S3Sync::CloudFront).not_to receive(:invalidate)

        Middleman::S3Sync.sync
      end
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
        bucket: 'test-bucket'
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
end
