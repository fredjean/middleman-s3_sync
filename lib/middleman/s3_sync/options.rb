module Middleman
  module S3Sync
    class Options
      OPTIONS = [
        :prefix,
        :http_prefix,
        :acl,
        :bucket,
        :endpoint,
        :region,
        :aws_access_key_id,
        :aws_secret_access_key,
        :after_build,
        :delete,
        :encryption,
        :existing_remote_file,
        :build_dir,
        :force,
        :prefer_gzip,
        :reduced_redundancy_storage,
        :path_style,
        :version_bucket,
        :dry_run,
        :verbose,
        :content_types,
        :ignore_paths,
        :index_document,
        :error_document
      ]
      attr_accessor *OPTIONS

      def acl
        # If @acl is explicitly set to empty string or false, return nil (for buckets with ACLs disabled)
        # If @acl is nil and was never set, return default 'public-read'
        # Otherwise return the set value
        return nil if @acl == '' || @acl == false
        @acl_explicitly_set ? @acl : (@acl || 'public-read')
      end

      def acl=(value)
        @acl_explicitly_set = true
        @acl = value
      end

      def acl_enabled?
        # ACLs are disabled if explicitly set to nil, empty string, or false
        return false if @acl_explicitly_set && (@acl.nil? || @acl == '' || @acl == false)
        # Otherwise ACLs are enabled (using default or explicit value)
        true
      end

      def aws_access_key_id=(aws_access_key_id)
        @aws_access_key_id = aws_access_key_id if aws_access_key_id
      end

      def aws_access_key_id
        @aws_access_key_id || ENV['AWS_ACCESS_KEY_ID']
      end

      def aws_secret_access_key=(aws_secret_access_key)
        @aws_secret_access_key = aws_secret_access_key if aws_secret_access_key
      end

      def aws_secret_access_key
        @aws_secret_access_key || ENV['AWS_SECRET_ACCESS_KEY']
      end

      def encryption
        @encryption.nil? ? false : @encryption
      end

      def delete
        @delete.nil? ? true : @delete
      end

      def after_build
        @after_build.nil? ? false : @after_build
      end

      def prefer_gzip
        (@prefer_gzip.nil? ? true : @prefer_gzip)
      end

      def path_style
        (@path_style.nil? ? true : @path_style)
      end

      def ignore_paths
        @ignore_paths.nil? ? [] : @ignore_paths
      end

      def prefix=(prefix)
        http_prefix = @http_prefix ? @http_prefix.sub(%r{^/}, "") : ""
        if http_prefix.split("/").first == prefix
          @prefix = ""
        else
          @prefix = prefix
        end
      end

      def prefix
        @prefix.nil? || @prefix.empty? ? "" : "#{@prefix}/"
      end

      def version_bucket
        @version_bucket.nil? ? false : @version_bucket
      end

    end
  end
end
