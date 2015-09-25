require 'spec_helper'

describe Middleman::S3Sync::Resource do

  let(:options) {
    Middleman::S3Sync::Options.new
  }

  let(:mm_resource) {
    double(
      destination_path: 'path/to/resource.html'
    )
  }
  before do
    Middleman::S3Sync.s3_sync_options = options
    options.build_dir = "build"
    options.prefer_gzip = false
  end

  context "a new resource" do
    subject(:resource) { Middleman::S3Sync::Resource.new(mm_resource, nil) }

    context "without a prefix" do
      before do
        allow(File).to receive(:exist?).with('build/path/to/resource.html').and_return(true)
      end

      its(:status) { should eq :new }

      it "does not have a remote equivalent" do
        expect(resource).not_to be_remote
      end

      it "exits locally" do
        expect(resource).to be_local
      end

      its(:path) { should eq 'path/to/resource.html'}
      its(:local_path) { should eq 'build/path/to/resource.html' }
      its(:remote_path) { should eq 'path/to/resource.html' }
    end

    context "with a prefix set" do
      before do
        allow(File).to receive(:exist?).with('build/path/to/resource.html').and_return(true)
        options.prefix = "bob"
      end

      it "does not have a remote equivalent" do
        expect(resource).not_to be_remote
      end

      it "exists locally" do
        expect(resource).to be_local
      end

      its(:path) { should eq 'path/to/resource.html' }
      its(:local_path) { should eq 'build/path/to/resource.html' }
      its(:remote_path) { should eq 'bob/path/to/resource.html' }
    end

    context "gzipped" do
      before do
        allow(File).to receive(:exist?).with('build/path/to/resource.html.gz').and_return(true)
        options.prefer_gzip = true
      end

      it "does not have a remote equivalent" do
        expect(resource).not_to be_remote
      end

      it "exists locally" do
        expect(resource).to be_local
      end

      its(:path) { should eq 'path/to/resource.html' }
      its(:local_path) { should eq 'build/path/to/resource.html.gz' }
      its(:remote_path) { should eq 'path/to/resource.html' }
    end
  end

  context "the file does not exist locally" do
    subject(:resource) { Middleman::S3Sync::Resource.new(nil, remote) }

    let(:remote) {
      double(
        key: 'path/to/resource.html',
        metadata: {}
      )
    }

    before do
      resource.full_s3_resource = remote
    end

    context "without a prefix" do
      before do
        allow(File).to receive(:exist?).with('build/path/to/resource.html').and_return(false)
      end

      its(:status) { should eq :deleted }
      it "does not have a remote equivalent" do
        expect(resource).to be_remote
      end

      it "exits locally" do
        expect(resource).not_to be_local
      end

      its(:path) { should eq 'path/to/resource.html'}
      its(:local_path) { should eq 'build/path/to/resource.html' }
      its(:remote_path) { should eq 'path/to/resource.html' }
    end

    context "with a prefix set" do
      before do
        allow(File).to receive(:exist?).with('build/path/to/resource.html').and_return(false)
        allow(remote).to receive(:key).and_return('bob/path/to/resource.html')
        options.prefix = "bob"
      end

      its(:status) { should eq :deleted }
      it "does not have a remote equivalent" do
        expect(resource).to be_remote
      end

      it "does not exist locally" do
        expect(resource).not_to be_local
      end

      its(:path) { should eq 'path/to/resource.html' }
      its(:local_path) { should eq 'build/path/to/resource.html' }
      its(:remote_path) { should eq 'bob/path/to/resource.html' }
    end

    context "gzipped" do
      before do
        allow(File).to receive(:exist?).with('build/path/to/resource.html.gz').and_return(false)
        allow(File).to receive(:exist?).with('build/path/to/resource.html').and_return(false)
        options.prefer_gzip = true
      end

      its(:status) { should eq :deleted }
      it "does not have a remote equivalent" do
        expect(resource).to be_remote
      end

      it "exists locally" do
        expect(resource).not_to be_local
      end

      its(:path) { should eq 'path/to/resource.html' }
      its(:local_path) { should eq 'build/path/to/resource.html' }
      its(:remote_path) { should eq 'path/to/resource.html' }
    end
  end
end
