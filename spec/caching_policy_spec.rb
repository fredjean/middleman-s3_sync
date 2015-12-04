require 'spec_helper'
require 'middleman/s3_sync/caching_policy'

describe Middleman::S3Sync::BrowserCachePolicy do
  context "building the policy" do
    let(:options) { Hash.new }
    subject(:policy) { Middleman::S3Sync::BrowserCachePolicy.new(options) }

    it "should be blank" do
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

    context "setting max-age" do
      let(:options) { { max_age: 300 } }

      its(:to_s) { should =~ /max-age=300/ }
    end

    context "setting s-maxage" do
      let(:options) { { s_maxage: 300 } }

      its(:to_s) { should =~ /s-maxage=300/ }
    end

    context "set public flag" do
      let(:options) { { public: true } }
      its(:to_s) { should =~ /public/ }
    end

    context "it should set the private flag if it is set to true" do
      let(:options) { { private: true } }
      its(:to_s) { should =~ /private/ }
    end

    context "it should set the no-cache flag when set property" do
      let(:options) { { no_cache: true }}
      its(:to_s) { should =~ /no-cache/ }
    end

    context "setting the no-store flag" do
      let(:options) { { no_store: true } }
      its(:to_s) { should =~ /no-store/ }
    end

    context "setting the must-revalidate policy" do
      let(:options) { { must_revalidate: true } }
      its(:to_s) { should =~ /must-revalidate/ }
    end

    context "setting the proxy-revalidate policy" do
      let(:options) { { proxy_revalidate: true } }
      its(:to_s) { should =~ /proxy-revalidate/ }
    end

    context "divide caching policiies with a comma and a space" do
      let(:options) { { :max_age => 300, :public => true } }

      it "splits policies eith commans and spaces" do
        policies = policy.to_s.split(/, /)
        policies.length.should == 2
        policies.first.should == 'max-age=300'
        policies.last.should == 'public'
      end
    end

    context "set the expiration date" do
      let(:options) { { expires: 1.years.from_now } }

      its(:expires) { should == CGI.rfc1123_date(1.year.from_now )}
    end
  end
end

describe "Storing and retrieving policies" do
  class CachingPolicy
    include Middleman::S3Sync::CachingPolicy
  end

  let(:caching_policy) { CachingPolicy.new }
  let(:policy) { caching_policy.caching_policy_for("text/html; charset=utf-8") }

  it "finds the policies by the mime-type excluding the parameters" do
    caching_policy.add_caching_policy("text/html", max_age: 300)

    expect(policy).to_not be_nil
    expect(policy.policies.max_age).to eq(300)
  end
end
