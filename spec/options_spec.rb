require 'spec_helper'
require 'middleman/s3_sync/options'

describe Middleman::S3Sync::Options do
  subject(:options) { Middleman::S3Sync::Options.new }

  its(:delete) { is_expected.to eq(true) }
  its(:after_build) { is_expected.to eq(false)}
  its(:prefer_gzip) { is_expected.to eq(true) }
  its(:aws_secret_access_key) { is_expected.to eq(ENV['AWS_SECRET_ACCESS_KEY']) }
  its(:aws_access_key_id) { is_expected.to eq(ENV['AWS_ACCESS_KEY_ID']) }
  its(:caching_policies) { is_expected.to be_empty }
  its(:default_caching_policy) { is_expected.to be_nil }

  context "browser caching policy" do
    let(:policy) { options.default_caching_policy }

    it "should have a blank default caching policy" do
      options.add_caching_policy :default, {}

      policy.should_not be_nil

      policy.to_s.should_not =~ /max-age=/
      policy.to_s.should_not =~ /s-maxage=/
      policy.to_s.should_not =~ /public/
      policy.to_s.should_not =~ /private/
      policy.to_s.should_not =~ /no-cache/
      policy.to_s.should_not =~ /no-store/
      policy.to_s.should_not =~ /must-revalidate/
      policy.to_s.should_not =~ /proxy-revalidate/
      policy.expires.should be_nil
    end

    it "should set the max-age policy" do
      options.add_caching_policy :default, :max_age => 300

      policy.to_s.should =~ /max-age=300/
    end

    it "should set the s-maxage policy" do
      options.add_caching_policy :default, :s_maxage => 300

      policy.to_s.should =~ /s-maxage=300/
    end

    it "should set the public flag on the policy if set to true" do
      options.add_caching_policy :default, :public => true

      policy.to_s.should =~ /public/
    end

    it "should not set the public flag on the policy if it is set to false" do
      options.add_caching_policy :default, :public => false

      policy.to_s.should_not =~ /public/
    end

    it "should set the private flag on the policy if it is set to true" do
      options.add_caching_policy :default, :private => true

      policy.to_s.should =~ /private/
    end

    it "should set the no-cache flag on the policy if it is set to true" do
      options.add_caching_policy :default, :no_cache => true

      policy.to_s.should =~ /no-cache/
    end

    it "should set the no-store flag if it is set to true" do
      options.add_caching_policy :default, :no_store => true

      policy.to_s.should =~ /no-store/
    end

    it "should set the must-revalidate policy if it is set to true" do
      options.add_caching_policy :default, :must_revalidate => true

      policy.to_s.should =~ /must-revalidate/
    end

    it "should set the proxy-revalidate policy if it is set to true" do
      options.add_caching_policy :default, :proxy_revalidate => true

      policy.to_s.should =~ /proxy-revalidate/
    end

    it "should divide caching policies with commas and a space" do
      options.add_caching_policy :default, :max_age => 300, :public => true

      policies = policy.to_s.split(/, /)
      policies.length.should == 2
      policies.first.should == 'max-age=300'
      policies.last.should == 'public'
    end

    it "should set the expiration date" do
      expiration = 1.years.from_now

      options.add_caching_policy :default, :expires => expiration
      policy.expires.should == CGI.rfc1123_date(expiration)
    end
  end

  context "#read_config" do
    let(:aws_access_key_id) { "foo" }
    let(:aws_secret_access_key) { "bar" }
    let(:bucket) { "baz" }
    let(:config) { { "aws_access_key_id" => aws_access_key_id, "aws_secret_access_key" => aws_secret_access_key, "bucket" => bucket } }
    let(:file) { StringIO.new(YAML.dump(config)) }

    before do
      options.read_config(file)
    end

    its(:aws_access_key_id) { should eq(aws_access_key_id) }
    its(:aws_secret_access_key) { should eq(aws_secret_access_key) }
    its(:bucket) { should eq(bucket) }
  end
end
