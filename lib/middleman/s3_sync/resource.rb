module Middleman
  module S3Sync
    class Resource
      attr_accessor :path, :local_path, :s3_resource, :content_type

      def initialize(path)
        @path = path
        @local_path = build_dir + '/' + path
        @s3_resource = bucket.files.get(path) rescue nil
      end

      def remote_path
        s3_resource ? s3_resource.key : path
      end
      alias :key :remote_path

      def to_h
        attributes = {
          :key => key,
          :body => body,
          :public => true,
          :acl => 'public-read',
          :content_type => content_type
        }

        if caching_policy
          attributes[:cache_control] = caching_policy.cache_control
          attributes[:expires] = caching_control.expires
        end

        attributes
      end
      alias :attributes :to_h

      def update!
        puts "Updating #{path}"
        s3_resource.body = body
        s3_resource.public = true
        s3_resource.acl = 'public-read'
        s3_resource.content_type = content_type
        if caching_policy
          file.cache_control = caching_policy.cache_control
          file.expires = caching_policy.expires
        end

        s3_resource.save
      end

      def destroy!
        puts "Deleting #{path}"
        s3_resource.destroy
      end

      def create!
        puts "Creating #{path}"
        bucket.files.create(to_h)
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

      def body
        @body = File.open(local_path)
      end

      def status
        @status ||= if local? && remote?
                      if local_md5 != remote_md5
                        :updated
                      else
                        :identical
                      end
                    elsif local?
                      :new
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

      def relative_path
        @relative_path ||= local_path.gsub(/#{build_dir}/, '')
      end

      def local_md5
        @local_md5 ||= Digest::MD5.hexdigest(File.read(local_path))
      end

      def remote_md5
        s3_resource.etag
      end

      def content_type
        @content_type ||= MIME::Types.of(local_path).first
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
