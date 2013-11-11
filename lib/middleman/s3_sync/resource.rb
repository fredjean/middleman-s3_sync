module Middleman
  module S3Sync
    class Resource
      attr_accessor :path, :s3_resource, :content_type, :gzipped

      CONTENT_MD5_KEY = 'x-amz-meta-content-md5'

      include Status

      def initialize(path)
        @path = path
        @s3_resource = bucket.files.head(path)
      end

      def remote_path
        s3_resource ? s3_resource.key : path
      end
      alias :key :remote_path

      def to_h
        attributes = {
          :key => "#{options.bucket_folder}#{key}",
          :body => body,
          :acl => options.acl,
          :content_type => content_type,
          CONTENT_MD5_KEY => content_md5
        }

        if caching_policy
          attributes[:cache_control] = caching_policy.cache_control
          attributes[:expires] = caching_policy.expires
        end

        if options.prefer_gzip && gzipped
          attributes[:content_encoding] = "gzip"
        end

        if options.reduced_redundancy_storage
          attributes[:storage_class] = 'REDUCED_REDUNDANCY'
        end

        if options.encryption
          attributes[:encryption] = 'AES256'
        end

        attributes
      end
      alias :attributes :to_h

      def update!
        say_status "Updating".blue + " #{path}#{ gzipped ? ' (gzipped)'.white : ''}"
        if options.verbose
          say_status "Original:    #{original_path.white}"
          say_status "Local Path:  #{local_path.white}"
          say_status "remote md5:  #{remote_md5.white}"
          say_status "content md5: #{content_md5.white}"
        end
        s3_resource.body = body
        s3_resource.acl = options.acl
        s3_resource.content_type = content_type
        s3_resource.metadata = { CONTENT_MD5_KEY => content_md5 }

        if caching_policy
          s3_resource.cache_control = caching_policy.cache_control
          s3_resource.expires = caching_policy.expires
        end

        if options.prefer_gzip && gzipped
          s3_resource.content_encoding = "gzip"
        end

        if options.reduced_redundancy_storage
          s3_resource.storage_class = 'REDUCED_REDUNDANCY'
        end

        if options.encryption
          s3_resource.encryption = 'AES256'
        end

        s3_resource.save
      end

      def local_path
        local_path = build_dir + '/' + path
        if options.prefer_gzip && File.exist?(local_path + ".gz")
          @gzipped = true
          local_path += ".gz"
        end
        local_path
      end

      def destroy!
        say_status "Deleting".red + " #{path}"
        s3_resource.destroy
      end

      def create!
        say_status "Creating".green + " #{path}#{ gzipped ? ' (gzipped)'.white : ''}"
        if options.verbose
          say_status "Original:    #{original_path.white}"
          say_status "Local Path:  #{local_path.white}"
          say_status "content md5: #{content_md5.white}"
        end
        bucket.files.create(to_h)
      end

      def ignore!
        reason = if redirect?
                   :redirect
                 elsif directory?
                   :directory
                 end
        say_status "Ignoring".yellow + " #{path} #{ reason ? "(#{reason})".white : "" }"
      end

      def to_delete?
        status == :deleted
      end

      def to_create?
        status == :new
      end

      def identical?
        status == :identical
      end

      def to_update?
        status == :updated
      end

      def to_ignore?
        status == :ignored
      end

      def body
        @body = File.open(local_path)
      end

      def status
        @status ||= if directory?
                      :ignored
                    elsif local? && remote?
                      if content_md5 != remote_md5
                        :updated
                      else
                        :identical
                      end
                    elsif local?
                      :new
                    elsif remote? && redirect?
                      :ignored
                    else
                      :deleted
                    end
      end

      def local?
        File.exist?(local_path)
      end

      def remote?
        s3_resource
      end

      def redirect?
        s3_resource.metadata.has_key?('x-amz-website-redirect-location')
      end

      def directory?
        File.directory?(local_path)
      end

      def relative_path
        @relative_path ||= local_path.gsub(/#{build_dir}/, '')
      end

      def remote_md5
        s3_resource.metadata[CONTENT_MD5_KEY] || s3_resource.etag
      end

      def content_md5
        @content_md5 ||= Digest::MD5.hexdigest(File.read(original_path))
      end

      def original_path
        gzipped ? local_path.gsub(/\.gz$/, '') : local_path
      end

      def content_type
        @content_type ||= MIME::Types.of(path).first
      end

      def caching_policy
        @caching_policy ||= options.caching_policy_for(content_type)
      end

      protected
      def bucket
        Middleman::S3Sync.bucket
      end

      def build_dir
        options.build_dir
      end

      def options
        Middleman::S3Sync.s3_sync_options
      end
    end
  end
end
