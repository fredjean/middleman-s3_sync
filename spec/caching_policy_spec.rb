require 'spec_helper'
require 'middleman/s3_sync/caching_policy'

describe Middleman::S3Sync::BrowserCachePolicy do
  context "building the policy" do
    let(:options) { Hash.new }
    subject(:policy) { Middleman::S3Sync::BrowserCachePolicy.new(options) }

    it "should be blank" do
      expect(policy).to_not eq nil

      expect(policy.to_s).to_not match /max-age=/
      expect(policy.to_s).to_not match /s-maxage=/
      expect(policy.to_s).to_not match /public/
      expect(policy.to_s).to_not match /private/
      expect(policy.to_s).to_not match /no-cache/
      expect(policy.to_s).to_not match /no-store/
      expect(policy.to_s).to_not match /must-revalidate/
      expect(policy.to_s).to_not match /proxy-revalidate/
      expect(policy.expires).to eq nil
    end

    context "setting max-age" do
      let(:options) { { max_age: 300 } }

      its(:to_s) { is_expected.to match /max-age=300/ }
    end

    context "setting s-maxage" do
      let(:options) { { s_maxage: 300 } }

      its(:to_s) { is_expected.to match /s-maxage=300/ }
    end

    context "set public flag" do
      let(:options) { { public: true } }
      its(:to_s) { is_expected.to match /public/ }
    end

    context "it should set the private flag if it is set to true" do
      let(:options) { { private: true } }
      its(:to_s) { is_expected.to match /private/ }
    end

    context "it should set the no-cache flag when set property" do
      let(:options) { { no_cache: true }}
      its(:to_s) { is_expected.to match /no-cache/ }
    end

    context "setting the no-store flag" do
      let(:options) { { no_store: true } }
      its(:to_s) { is_expected.to match /no-store/ }
    end

    context "setting the must-revalidate policy" do
      let(:options) { { must_revalidate: true } }
      its(:to_s) { is_expected.to match /must-revalidate/ }
    end

    context "setting the proxy-revalidate policy" do
      let(:options) { { proxy_revalidate: true } }
      its(:to_s) { is_expected.to match /proxy-revalidate/ }
    end

    context "divide caching policiies with a comma and a space" do
      let(:options) { { :max_age => 300, :public => true } }

      it "splits policies eith commans and spaces" do
        policies = policy.to_s.split(/, /)
        expect(policies.length).to eq 2
        expect(policies.first).to eq 'max-age=300'
        expect(policies.last).to eq 'public'
      end
    end

    context "set the expiration date" do
      let(:options) { { expires: 1.years.from_now } }

      its(:expires) { is_expected.to eq CGI.rfc1123_date(1.year.from_now )}
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

    expect(policy).to_not eq nil
    expect(policy.policies.max_age).to eq(300)
  end
end

describe "Handling situations where the content type is nil" do
  class CachingPolicy
    include Middleman::S3Sync::CachingPolicy
  end

  let(:caching_policy) { CachingPolicy.new }

  it "returns the default caching policy when the content type is nil" do
    caching_policy.add_caching_policy(:default, max_age:(60 * 60 * 24 * 365))

    expect(caching_policy.caching_policy_for(nil)).to_not eq nil
    expect(caching_policy.caching_policy_for(nil).policies[:max_age]).to eq(60 * 60 * 24 * 365)
  end

  it "returns the default caching policy when the content type is blank" do
    caching_policy.add_caching_policy(:default, max_age:(60 * 60 * 24 * 365))

    expect(caching_policy.caching_policy_for("")).to_not eq nil
    expect(caching_policy.caching_policy_for("").policies[:max_age]).to eq(60 * 60 * 24 * 365)
  end
end
