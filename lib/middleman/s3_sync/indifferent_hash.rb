module Middleman
  module S3Sync
    # A simple hash wrapper that provides string/symbol indifferent access
    # This replaces the Map gem dependency with native Ruby functionality
    class IndifferentHash < Hash
      # Convert keys to strings for consistent access
      def normalize_key(key)
        key.to_s
      end

      # Override [] to provide indifferent access
      def [](key)
        super(normalize_key(key))
      end

      # Override []= to store with normalized keys
      def []=(key, value)
        super(normalize_key(key), value)
      end

      # Override fetch to provide indifferent access
      def fetch(key, *args, &block)
        super(normalize_key(key), *args, &block)
      end

      # Override has_key? to work with normalized keys
      def has_key?(key)
        super(normalize_key(key))
      end
      alias_method :key?, :has_key?
      alias_method :include?, :has_key?

      # Create an IndifferentHash from a regular hash
      def self.from_hash(hash)
        new_hash = new
        hash.each do |key, value|
          new_hash[key] = value
        end
        new_hash
      end

      # Provide dot notation access to hash values
      def method_missing(method, *args, &block)
        key = method.to_s
        if key.end_with?('=')
          # Handle setter: hash.key = value
          self[key.chop] = args.first
        elsif has_key?(key)
          # Handle getter: hash.key
          self[key]
        else
          super
        end
      end

      def respond_to_missing?(method, include_private = false)
        key = method.to_s.sub(/=$/, '')
        has_key?(key) || super
      end
    end
  end
end
