require 'spec_helper'
require 'middleman/s3_sync/cloudfront'

describe Middleman::S3Sync::CloudFront do
  let(:options) do
    double(
      cloudfront_invalidate: true,
      cloudfront_distribution_id: 'E1234567890123',
      cloudfront_invalidate_all: false,
      cloudfront_invalidation_batch_size: 1000,
      cloudfront_invalidation_max_retries: 5,
      cloudfront_invalidation_batch_delay: 2,
      cloudfront_wait: false,
      aws_access_key_id: 'test_key',
      aws_secret_access_key: 'test_secret',
      aws_session_token: nil,
      dry_run: false,
      verbose: false
    )
  end

  let(:invalidation_response) do
    double(
      invalidation: double(id: 'I1234567890123')
    )
  end

  before do
    allow(described_class).to receive(:say_status)
  end

  describe '.invalidate' do
    context 'when CloudFront invalidation is disabled' do
      let(:options) do
        double(cloudfront_invalidate: false)
      end

      it 'returns early without doing anything' do
        expect(Aws::CloudFront::Client).not_to receive(:new)
        result = described_class.invalidate(['/path1', '/path2'], options)
        expect(result).to be_nil
      end
    end

    context 'when no distribution ID is provided' do
      let(:options) do
        double(
          cloudfront_invalidate: true,
          cloudfront_distribution_id: nil
        )
      end

      it 'skips invalidation and shows warning' do
        expect(described_class).to receive(:say_status).with(
          match(/CloudFront invalidation skipped.*no distribution ID/)
        )
        expect(Aws::CloudFront::Client).not_to receive(:new)
        result = described_class.invalidate(['/path1', '/path2'], options)
        expect(result).to be_nil
      end
    end

    context 'when dry run is enabled' do
      let(:options) do
        double(
          cloudfront_invalidate: true,
          cloudfront_distribution_id: 'E1234567890123',
          cloudfront_invalidate_all: false,
          dry_run: true,
          verbose: true
        )
      end

      it 'shows what would be invalidated without making API calls' do
        expect(described_class).to receive(:say_status).with(
          'Invalidating CloudFront distribution E1234567890123'
        )
        expect(described_class).to receive(:say_status).with(
          match(/DRY RUN.*Would invalidate 2 paths/)
        )
        expect(described_class).to receive(:say_status).with('  /path1')
        expect(described_class).to receive(:say_status).with('  /path2')
        expect(Aws::CloudFront::Client).not_to receive(:new)

        result = described_class.invalidate(['/path1', '/path2'], options)
        expect(result).to be_nil
      end
    end

    context 'when invalidating all paths' do
      let(:options) do
        double(
          cloudfront_invalidate: true,
          cloudfront_distribution_id: 'E1234567890123',
          cloudfront_invalidate_all: true,
          cloudfront_invalidation_batch_size: 1000,
          cloudfront_invalidation_max_retries: 5,
          cloudfront_invalidation_batch_delay: 2,
          cloudfront_wait: false,
          aws_access_key_id: 'test_key',
          aws_secret_access_key: 'test_secret',
          aws_session_token: nil,
          dry_run: false,
          verbose: false
        )
      end

      it 'invalidates all paths with /*' do
        client = double('cloudfront_client')
        allow(Aws::CloudFront::Client).to receive(:new).and_return(client)
        expect(client).to receive(:create_invalidation).with({
          distribution_id: 'E1234567890123',
          invalidation_batch: {
            paths: {
              quantity: 1,
              items: ['/*']
            },
            caller_reference: match(/middleman-s3_sync-\d+-[a-f0-9]{8}/)
          }
        }).and_return(invalidation_response)

        result = described_class.invalidate(['/path1', '/path2'], options)
        expect(result).to eq(['I1234567890123'])
      end
    end

    context 'when invalidating specific paths' do
      it 'creates invalidation for the provided paths' do
        client = double('cloudfront_client')
        allow(Aws::CloudFront::Client).to receive(:new).and_return(client)
        expect(client).to receive(:create_invalidation).with({
          distribution_id: 'E1234567890123',
          invalidation_batch: {
            paths: {
              quantity: 2,
              items: ['/path1', '/path2']
            },
            caller_reference: match(/middleman-s3_sync-\d+-[a-f0-9]{8}/)
          }
        }).and_return(invalidation_response)

        result = described_class.invalidate(['/path1', '/path2'], options)
        expect(result).to eq(['I1234567890123'])
      end

      it 'normalizes paths to start with /' do
        client = double('cloudfront_client')
        allow(Aws::CloudFront::Client).to receive(:new).and_return(client)
        expect(client).to receive(:create_invalidation).with({
          distribution_id: 'E1234567890123',
          invalidation_batch: {
            paths: {
              quantity: 2,
              items: ['/path1', '/path2']
            },
            caller_reference: match(/middleman-s3_sync-\d+-[a-f0-9]{8}/)
          }
        }).and_return(invalidation_response)

        result = described_class.invalidate(['path1', '/path2'], options)
        expect(result).to eq(['I1234567890123'])
      end

      it 'removes duplicate paths' do
        client = double('cloudfront_client')
        allow(Aws::CloudFront::Client).to receive(:new).and_return(client)
        expect(client).to receive(:create_invalidation).with({
          distribution_id: 'E1234567890123',
          invalidation_batch: {
            paths: {
              quantity: 2,
              items: ['/path1', '/path2']
            },
            caller_reference: match(/middleman-s3_sync-\d+-[a-f0-9]{8}/)
          }
        }).and_return(invalidation_response)

        result = described_class.invalidate(['/path1', 'path1', '/path2'], options)
        expect(result).to eq(['I1234567890123'])
      end

      it 'removes double slashes from paths' do
        client = double('cloudfront_client')
        allow(Aws::CloudFront::Client).to receive(:new).and_return(client)
        expect(client).to receive(:create_invalidation).with({
          distribution_id: 'E1234567890123',
          invalidation_batch: {
            paths: {
              quantity: 1,
              items: ['/path/to/file.html']
            },
            caller_reference: match(/middleman-s3_sync-\d+-[a-f0-9]{8}/)
          }
        }).and_return(invalidation_response)

        result = described_class.invalidate(['//path//to//file.html'], options)
        expect(result).to eq(['I1234567890123'])
      end
    end

    context 'with large batch sizes' do
      let(:options) do
        double(
          cloudfront_invalidate: true,
          cloudfront_distribution_id: 'E1234567890123',
          cloudfront_invalidate_all: false,
          cloudfront_invalidation_batch_size: 2,
          cloudfront_invalidation_max_retries: 5,
          cloudfront_invalidation_batch_delay: 1,
          cloudfront_wait: false,
          aws_access_key_id: 'test_key',
          aws_secret_access_key: 'test_secret',
          aws_session_token: nil,
          dry_run: false,
          verbose: false
        )
      end

      it 'splits paths into multiple batches' do
        client = double('cloudfront_client')
        allow(Aws::CloudFront::Client).to receive(:new).and_return(client)
        paths = ['/path1', '/path2', '/path3', '/path4']
        
        expect(client).to receive(:create_invalidation).twice.and_return(invalidation_response)
        expect(described_class).to receive(:sleep).with(1)

        result = described_class.invalidate(paths, options)
        expect(result).to eq(['I1234567890123', 'I1234567890123'])
      end
    end

    context 'when CloudFront API returns an error' do
      let(:error) { Aws::CloudFront::Errors::ServiceError.new(nil, 'Distribution not found') }

      it 'handles API errors gracefully' do
        client = double('cloudfront_client')
        allow(Aws::CloudFront::Client).to receive(:new).and_return(client)
        expect(client).to receive(:create_invalidation).and_raise(error)
        expect(described_class).to receive(:say_status).with(
          match(/Failed to create CloudFront invalidation.*Distribution not found/)
        )

        expect {
          described_class.invalidate(['/path1'], options)
        }.to raise_error(Aws::CloudFront::Errors::ServiceError)
      end

      context 'when rate limit is exceeded' do
        let(:rate_error) { Aws::CloudFront::Errors::ServiceError.new(nil, 'Rate exceeded') }

        it 'retries with exponential backoff' do
          client = double('cloudfront_client')
          allow(Aws::CloudFront::Client).to receive(:new).and_return(client)
          
          # Fail twice with rate limit, then succeed
          call_count = 0
          allow(client).to receive(:create_invalidation) do
            call_count += 1
            if call_count <= 2
              raise rate_error
            else
              invalidation_response
            end
          end
          
          # Allow normal status messages but expect retry messages
          allow(described_class).to receive(:say_status)
          expect(described_class).to receive(:say_status).with(
            match(/Rate limit hit, retrying in \d+ seconds.*attempt 1\/5/)
          ).ordered
          expect(described_class).to receive(:say_status).with(
            match(/Rate limit hit, retrying in \d+ seconds.*attempt 2\/5/)
          ).ordered
          
          # Expect sleep calls for backoff
          expect(described_class).to receive(:sleep).twice
          
          result = described_class.invalidate(['/path1'], options)
          expect(result).to eq(['I1234567890123'])
        end

        it 'gives up after max retries and raises error' do
          rate_limited_options = double(
            cloudfront_invalidate: true,
            cloudfront_distribution_id: 'E1234567890123',
            cloudfront_invalidate_all: false,
            cloudfront_invalidation_batch_size: 1000,
            cloudfront_invalidation_max_retries: 2,
            cloudfront_invalidation_batch_delay: 2,
            cloudfront_wait: false,
            aws_access_key_id: 'test_key',
            aws_secret_access_key: 'test_secret',
            aws_session_token: nil,
            dry_run: false,
            verbose: false
          )
          
          client = double('cloudfront_client')
          allow(Aws::CloudFront::Client).to receive(:new).and_return(client)
          
          # Fail max_retries + 1 times
          expect(client).to receive(:create_invalidation).exactly(3).times.and_raise(rate_error)
          
          # Allow normal status messages
          allow(described_class).to receive(:say_status)
          
          # Expect retry status messages
          expect(described_class).to receive(:say_status).with(
            match(/Rate limit hit, retrying in \d+ seconds.*attempt 1\/2/)
          )
          expect(described_class).to receive(:say_status).with(
            match(/Rate limit hit, retrying in \d+ seconds.*attempt 2\/2/)
          )
          expect(described_class).to receive(:say_status).with(
            match(/Failed to create CloudFront invalidation.*Rate exceeded/)
          )
          
          # Expect sleep calls for backoff
          expect(described_class).to receive(:sleep).twice
          
          expect {
            described_class.invalidate(['/path1'], rate_limited_options)
          }.to raise_error(Aws::CloudFront::Errors::ServiceError)
        end

        it 'handles throttling errors the same as rate exceeded' do
          throttling_error = Aws::CloudFront::Errors::ServiceError.new(nil, 'Throttling: Request was throttled')
          
          client = double('cloudfront_client')
          allow(Aws::CloudFront::Client).to receive(:new).and_return(client)
          
          call_count = 0
          allow(client).to receive(:create_invalidation) do
            call_count += 1
            if call_count == 1
              raise throttling_error
            else
              invalidation_response
            end
          end
          
          # Allow normal status messages but expect retry message
          allow(described_class).to receive(:say_status)
          expect(described_class).to receive(:say_status).with(
            match(/Rate limit hit, retrying in \d+ seconds.*attempt 1\/5/)
          ).ordered
          expect(described_class).to receive(:sleep).once
          
          result = described_class.invalidate(['/path1'], options)
          expect(result).to eq(['I1234567890123'])
        end
      end

      context 'when verbose mode is enabled' do
        let(:options) do
          double(
            cloudfront_invalidate: true,
            cloudfront_distribution_id: 'E1234567890123',
            cloudfront_invalidate_all: false,
            cloudfront_invalidation_batch_size: 1000,
            cloudfront_invalidation_max_retries: 5,
            cloudfront_invalidation_batch_delay: 2,
            cloudfront_wait: false,
            aws_access_key_id: 'test_key',
            aws_secret_access_key: 'test_secret',
            aws_session_token: nil,
            dry_run: false,
            verbose: true
          )
        end

        it 'does not re-raise errors in verbose mode' do
          client = double('cloudfront_client')
          allow(Aws::CloudFront::Client).to receive(:new).and_return(client)
          expect(client).to receive(:create_invalidation).and_raise(error)
          expect(described_class).to receive(:say_status).with(
            match(/Failed to create CloudFront invalidation/)
          )

          expect {
            described_class.invalidate(['/path1'], options)
          }.not_to raise_error
        end
      end
    end

    context 'with empty paths and invalidate_all false' do
      it 'returns early without making API calls' do
        expect(Aws::CloudFront::Client).not_to receive(:new)
        result = described_class.invalidate([], options)
        expect(result).to be_nil
      end
    end

    context 'when cloudfront_wait is enabled' do
      let(:options) do
        double(
          cloudfront_invalidate: true,
          cloudfront_distribution_id: 'E1234567890123',
          cloudfront_invalidate_all: false,
          cloudfront_invalidation_batch_size: 1000,
          cloudfront_invalidation_max_retries: 5,
          cloudfront_invalidation_batch_delay: 2,
          cloudfront_wait: true,
          aws_access_key_id: 'test_key',
          aws_secret_access_key: 'test_secret',
          aws_session_token: nil,
          dry_run: false,
          verbose: false
        )
      end

      it 'waits for invalidation to complete' do
        client = double('cloudfront_client')
        allow(Aws::CloudFront::Client).to receive(:new).and_return(client)
        expect(client).to receive(:create_invalidation).and_return(invalidation_response)
        expect(client).to receive(:wait_until).with(:invalidation_completed, 
          distribution_id: 'E1234567890123',
          id: 'I1234567890123'
        )
        expect(described_class).to receive(:say_status).with(
          'Waiting for CloudFront invalidation(s) to complete...'
        )
        expect(described_class).to receive(:say_status).with(
          'CloudFront invalidation(s) completed successfully'
        )

        result = described_class.invalidate(['/path1'], options)
        expect(result).to eq(['I1234567890123'])
      end
    end
  end

  describe 'CloudFront client configuration' do
    it 'creates client with correct credentials' do
      client = double('cloudfront_client')
      expect(Aws::CloudFront::Client).to receive(:new).with({
        region: 'us-east-1',
        access_key_id: 'test_key',
        secret_access_key: 'test_secret'
      }).and_return(client)

      expect(client).to receive(:create_invalidation).and_return(invalidation_response)

      described_class.invalidate(['/test'], options)
    end

    context 'with session token' do
      let(:options) do
        double(
          cloudfront_invalidate: true,
          cloudfront_distribution_id: 'E1234567890123',
          cloudfront_invalidate_all: false,
          cloudfront_invalidation_batch_size: 1000,
          cloudfront_invalidation_max_retries: 5,
          cloudfront_invalidation_batch_delay: 2,
          cloudfront_wait: false,
          aws_access_key_id: 'test_key',
          aws_secret_access_key: 'test_secret',
          aws_session_token: 'test_token',
          dry_run: false,
          verbose: false
        )
      end

      it 'includes session token in client configuration' do
        client = double('cloudfront_client')
        expect(Aws::CloudFront::Client).to receive(:new).with({
          region: 'us-east-1',
          access_key_id: 'test_key',
          secret_access_key: 'test_secret',
          session_token: 'test_token'
        }).and_return(client)

        expect(client).to receive(:create_invalidation).and_return(invalidation_response)

        described_class.invalidate(['/test'], options)
      end
    end

    context 'without explicit credentials' do
      let(:options) do
        double(
          cloudfront_invalidate: true,
          cloudfront_distribution_id: 'E1234567890123',
          cloudfront_invalidate_all: false,
          cloudfront_invalidation_batch_size: 1000,
          cloudfront_invalidation_max_retries: 5,
          cloudfront_invalidation_batch_delay: 2,
          cloudfront_wait: false,
          aws_access_key_id: nil,
          aws_secret_access_key: nil,
          aws_session_token: nil,
          dry_run: false,
          verbose: false
        )
      end

      it 'creates client without explicit credentials (uses default chain)' do
        client = double('cloudfront_client')
        expect(Aws::CloudFront::Client).to receive(:new).with({
          region: 'us-east-1'
        }).and_return(client)

        expect(client).to receive(:create_invalidation).and_return(invalidation_response)

        described_class.invalidate(['/test'], options)
      end
    end
  end
end