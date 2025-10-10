require 'spec_helper'

describe Middleman::S3SyncExtension do
  let(:app) { double('app').as_null_object }
  
  let(:extension) { described_class.new(app, {}) }

  describe '#acl_enabled?' do
    context 'when acl has default value' do
      it 'returns true' do
        expect(extension.acl_enabled?).to be true
      end
    end

    context 'when acl is explicitly set to a value' do
      let(:extension) { described_class.new(app, acl: 'private') }

      it 'returns true' do
        expect(extension.acl_enabled?).to be true
      end
    end

    context 'when acl is set to nil' do
      let(:extension) { described_class.new(app, acl: nil) }

      it 'returns false' do
        expect(extension.acl_enabled?).to be false
      end
    end

    context 'when acl is set to empty string' do
      let(:extension) { described_class.new(app, acl: '') }

      it 'returns false' do
        expect(extension.acl_enabled?).to be false
      end
    end

    context 'when acl is set to false' do
      let(:extension) { described_class.new(app, acl: false) }

      it 'returns false' do
        expect(extension.acl_enabled?).to be false
      end
    end
  end

  describe '#s3_sync_options' do
    it 'returns the extension instance itself' do
      expect(extension.s3_sync_options).to eq(extension)
    end

    it 'allows access to acl_enabled? through s3_sync_options' do
      expect(extension.s3_sync_options.acl_enabled?).to be true
    end
  end

  describe 'option delegation' do
    let(:extension) do
      described_class.new(app, 
        bucket: 'test-bucket',
        region: 'us-west-2',
        acl: 'public-read',
        verbose: true
      )
    end

    it 'delegates option readers to the options object' do
      expect(extension.bucket).to eq('test-bucket')
      expect(extension.region).to eq('us-west-2')
      expect(extension.acl).to eq('public-read')
      expect(extension.verbose).to be true
    end

    it 'responds to option methods' do
      expect(extension.respond_to?(:bucket)).to be true
      expect(extension.respond_to?(:region)).to be true
      expect(extension.respond_to?(:acl)).to be true
      expect(extension.respond_to?(:verbose)).to be true
    end

    it 'does not respond to non-existent methods' do
      expect(extension.respond_to?(:nonexistent_method)).to be false
    end

    it 'raises NoMethodError for non-existent methods' do
      expect { extension.nonexistent_method }.to raise_error(NoMethodError)
    end
  end

  describe 'integration with S3Sync module' do
    before do
      allow(Middleman::Application).to receive(:root).and_return('/tmp')
      allow(File).to receive(:exist?).with('/tmp/.s3_sync').and_return(false)
    end

    let(:extension) do
      described_class.new(app,
        bucket: 'test-bucket',
        acl: 'private'
      )
    end

    it 'sets s3_sync_options to the extension instance' do
      extension.after_configuration
      expect(Middleman::S3Sync.s3_sync_options).to eq(extension)
    end

    it 'allows S3Sync to access acl_enabled? through s3_sync_options' do
      extension.after_configuration
      expect(Middleman::S3Sync.s3_sync_options.acl_enabled?).to be true
    end
  end
end
