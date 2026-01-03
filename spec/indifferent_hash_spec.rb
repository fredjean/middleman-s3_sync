require 'spec_helper'

describe Middleman::S3Sync::IndifferentHash do
  let(:hash) { described_class.new }

  describe 'string-indifferent key access' do
    it 'allows setting and retrieving values using string keys' do
      hash['foo'] = 'bar'
      expect(hash['foo']).to eq('bar')
    end

    it 'retrieves string key values using symbol keys' do
      hash['foo'] = 'bar'
      expect(hash[:foo]).to eq('bar')
    end

    it 'normalizes string keys on retrieval' do
      hash['foo'] = 'value1'
      hash['foo'] = 'value2'
      expect(hash['foo']).to eq('value2')
      expect(hash.keys.count).to eq(1)
    end
  end

  describe 'symbol-indifferent key access' do
    it 'allows setting and retrieving values using symbol keys' do
      hash[:foo] = 'bar'
      expect(hash[:foo]).to eq('bar')
    end

    it 'retrieves symbol key values using string keys' do
      hash[:foo] = 'bar'
      expect(hash['foo']).to eq('bar')
    end

    it 'normalizes symbol keys to strings' do
      hash[:foo] = 'value1'
      hash['foo'] = 'value2'
      expect(hash[:foo]).to eq('value2')
      expect(hash.keys.count).to eq(1)
    end

    it 'stores keys as strings internally' do
      hash[:foo] = 'bar'
      expect(hash.keys).to eq(['foo'])
    end
  end

  describe 'dot notation access' do
    it 'allows accessing values using dot notation' do
      hash[:foo] = 'bar'
      expect(hash.foo).to eq('bar')
    end

    it 'allows setting values using dot notation' do
      hash.foo = 'baz'
      expect(hash[:foo]).to eq('baz')
    end

    it 'works with string keys' do
      hash['foo'] = 'bar'
      expect(hash.foo).to eq('bar')
    end

    it 'raises NoMethodError for non-existent keys' do
      expect { hash.nonexistent_key }.to raise_error(NoMethodError)
    end

    it 'supports respond_to? for existing keys' do
      hash[:foo] = 'bar'
      expect(hash).to respond_to(:foo)
      expect(hash).to respond_to(:foo=)
    end

    it 'returns false for respond_to? on non-existent keys' do
      expect(hash).not_to respond_to(:nonexistent)
    end
  end

  describe 'nested hashes with indifferent access' do
    it 'handles nested hash values' do
      hash[:outer] = { inner: 'value' }
      expect(hash[:outer]).to eq({ inner: 'value' })
    end

    it 'allows nested IndifferentHash instances' do
      inner = described_class.new
      inner[:foo] = 'bar'
      hash[:outer] = inner
      
      expect(hash[:outer][:foo]).to eq('bar')
      expect(hash[:outer].foo).to eq('bar')
    end

    it 'supports multiple levels of nesting' do
      inner = described_class.new
      inner[:level2] = 'deep'
      hash[:level1] = inner
      
      expect(hash['level1']['level2']).to eq('deep')
      expect(hash[:level1][:level2]).to eq('deep')
    end
  end

  describe 'Hash method compatibility' do
    describe '#has_key?' do
      it 'works with string keys' do
        hash['foo'] = 'bar'
        expect(hash.has_key?('foo')).to be true
        expect(hash.has_key?(:foo)).to be true
      end

      it 'works with symbol keys' do
        hash[:foo] = 'bar'
        expect(hash.has_key?('foo')).to be true
        expect(hash.has_key?(:foo)).to be true
      end

      it 'returns false for non-existent keys' do
        expect(hash.has_key?('nonexistent')).to be false
        expect(hash.has_key?(:nonexistent)).to be false
      end
    end

    describe '#key?' do
      it 'is aliased to has_key?' do
        hash[:foo] = 'bar'
        expect(hash.key?('foo')).to be true
        expect(hash.key?(:foo)).to be true
      end
    end

    describe '#include?' do
      it 'is aliased to has_key?' do
        hash[:foo] = 'bar'
        expect(hash.include?('foo')).to be true
        expect(hash.include?(:foo)).to be true
      end
    end

    describe '#fetch' do
      it 'fetches values with string keys' do
        hash['foo'] = 'bar'
        expect(hash.fetch('foo')).to eq('bar')
        expect(hash.fetch(:foo)).to eq('bar')
      end

      it 'fetches values with symbol keys' do
        hash[:foo] = 'bar'
        expect(hash.fetch('foo')).to eq('bar')
        expect(hash.fetch(:foo)).to eq('bar')
      end

      it 'returns default value for missing keys' do
        expect(hash.fetch('missing', 'default')).to eq('default')
        expect(hash.fetch(:missing, 'default')).to eq('default')
      end

      it 'calls block for missing keys' do
        result = hash.fetch('missing') { |key| "Key #{key} not found" }
        expect(result).to eq('Key missing not found')
      end

      it 'raises KeyError when key is missing without default' do
        expect { hash.fetch('missing') }.to raise_error(KeyError)
        expect { hash.fetch(:missing) }.to raise_error(KeyError)
      end
    end
  end

  describe '.from_hash' do
    it 'creates an IndifferentHash from a regular hash' do
      regular_hash = { 'foo' => 'bar', 'baz' => 'qux' }
      result = described_class.from_hash(regular_hash)
      
      expect(result).to be_a(described_class)
      expect(result['foo']).to eq('bar')
      expect(result[:foo]).to eq('bar')
      expect(result['baz']).to eq('qux')
      expect(result[:baz]).to eq('qux')
    end

    it 'handles hashes with symbol keys' do
      regular_hash = { foo: 'bar', baz: 'qux' }
      result = described_class.from_hash(regular_hash)
      
      expect(result[:foo]).to eq('bar')
      expect(result['foo']).to eq('bar')
    end

    it 'handles empty hashes' do
      result = described_class.from_hash({})
      expect(result).to be_a(described_class)
      expect(result).to be_empty
    end

    it 'handles mixed string and symbol keys' do
      regular_hash = { 'string_key' => 'value1', :symbol_key => 'value2' }
      result = described_class.from_hash(regular_hash)
      
      expect(result['string_key']).to eq('value1')
      expect(result[:string_key]).to eq('value1')
      expect(result['symbol_key']).to eq('value2')
      expect(result[:symbol_key]).to eq('value2')
    end
  end

  describe 'map gem API compatibility' do
    # These tests ensure no breaking changes compared to the map gem
    
    it 'supports basic key-value storage' do
      hash[:key] = 'value'
      expect(hash[:key]).to eq('value')
      expect(hash['key']).to eq('value')
    end

    it 'supports dot notation like map gem' do
      hash.max_age = 3600
      expect(hash.max_age).to eq(3600)
      expect(hash[:max_age]).to eq(3600)
    end

    it 'supports fetch with default values' do
      expect(hash.fetch(:missing, 'default')).to eq('default')
    end

    it 'supports has_key? checks' do
      hash[:present] = 'value'
      expect(hash.has_key?(:present)).to be true
      expect(hash.has_key?('present')).to be true
      expect(hash.has_key?(:absent)).to be false
    end

    it 'maintains Hash inheritance' do
      expect(hash).to be_a(Hash)
    end

    it 'supports standard Hash operations' do
      hash[:a] = 1
      hash[:b] = 2
      
      expect(hash.keys.sort).to eq(['a', 'b'])
      expect(hash.values.sort).to eq([1, 2])
      expect(hash.size).to eq(2)
    end

    it 'supports iteration' do
      hash[:a] = 1
      hash[:b] = 2
      
      result = []
      hash.each { |k, v| result << [k, v] }
      expect(result).to contain_exactly(['a', 1], ['b', 2])
    end

    context 'usage in BrowserCachePolicy' do
      it 'supports caching policy access patterns' do
        # Mimics how BrowserCachePolicy uses the hash
        hash[:max_age] = 3600
        hash[:s_maxage] = 7200
        hash[:public] = true
        hash[:no_cache] = false
        
        expect(hash.has_key?(:max_age)).to be true
        expect(hash.has_key?('s_maxage')).to be true
        expect(hash.fetch(:public, false)).to be true
        expect(hash.fetch(:private, false)).to be false
        expect(hash.fetch('must_revalidate', false)).to be false
      end

      it 'supports mixed string and symbol key access like in caching_policy.rb' do
        hash[:max_age] = 3600
        expect(hash['max_age']).to eq(3600)
        expect(hash.max_age).to eq(3600)
      end
    end
  end
end
