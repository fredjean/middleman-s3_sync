module Middleman
  module S3Sync
    class Options
      OPTIONS = [
        :prefix,
        :http_prefix,
        :acl,
        :bucket,
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
        :index_document,
        :error_document
      ]
      attr_accessor *OPTIONS

      def acl
        @acl || 'public-read'
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
