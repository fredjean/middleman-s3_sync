require 'spec_helper'
require 'middleman/s3_sync/options'

describe Middleman::S3Sync::Options do
  subject(:options) { Middleman::S3Sync::Options.new }

  its(:delete) { should be_true }
  its(:after_build) { should be_false }
  its(:prefer_gzip) { should be_true }
  its(:aws_secret_access_key) { should == ENV['AWS_SECRET_ACCESS_KEY'] }
  its(:aws_access_key_id) { should == ENV['AWS_ACCESS_KEY_ID'] }
  its(:caching_policies) { should be_empty }
  its(:default_caching_policy) { should be_nil }

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
  end
end
