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
        :verbose
      ]
      attr_accessor *OPTIONS

      def initialize
        # read config from .s3_sync on initialization
        self.read_config
      end

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
        @prefix.blank? ? "" : "#{@prefix}/"
      end

      def version_bucket
        @version_bucket.nil? ? false : @version_bucket
      end

      # Read config options from an IO stream and set them on `self`. Defaults
      # to reading from the `.s3_sync` file in the MM project root if it exists.
      #
      # @param io [IO] an IO stream to read from
      # @return [void]
      def read_config(io = nil)
        unless io
          root_path = ::Middleman::Application.root
          config_file_path = File.join(root_path, ".s3_sync")

          # skip if config file does not exist
          return unless File.exists?(config_file_path)

          io = File.open(config_file_path, "r")
        end

        config = YAML.load(io).symbolize_keys

        OPTIONS.each do |config_option|
          self.send("#{config_option}=".to_sym, config[config_option]) if config[config_option]
        end
      end
    end
  end
end
