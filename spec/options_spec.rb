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
end
