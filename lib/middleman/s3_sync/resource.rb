module Middleman
  module S3Sync
    class Resource
      attr_accessor :path, :resource, :partial_s3_resource, :full_s3_resource, :content_type, :gzipped, :options

      CONTENT_MD5_KEY = 'x-amz-meta-content-md5'
      REDIRECT_KEY = 'x-amz-website-redirect-location'

      include Status

      def initialize(resource, partial_s3_resource)
        @resource = resource
        @path = resource ? resource.destination_path : partial_s3_resource.key
        @partial_s3_resource = partial_s3_resource
      end

      def s3_resource
        @full_s3_resource || @partial_s3_resource
      end

      # S3 resource as returned by a HEAD request
      def full_s3_resource
        @full_s3_resource ||= begin
          bucket.object(remote_path).head
        rescue Aws::S3::Errors::NotFound
          nil
        end
      end

      def remote_path
        s3_resource ? s3_resource.key : "#{options.prefix}#{path}"
      end
      alias :key :remote_path

      def to_h
        attributes = {
          :key => key,
          :acl => options.acl,
          :content_type => content_type,
          CONTENT_MD5_KEY => local_content_md5
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

        if redirect?
          attributes[REDIRECT_KEY] = redirect_url
        end

        attributes
      end
      alias :attributes :to_h

      def update!
        say_status "#{ANSI.blue{"Updating"}} #{remote_path}#{ gzipped ? ANSI.white {' (gzipped)'} : ''}"
        unless options.dry_run
          upload!
        end
      end

      def local_path
        local_path = build_dir + '/' + path.gsub(/^#{options.prefix}/, '')
        if options.prefer_gzip && File.exist?(local_path + ".gz")
          @gzipped = true
          local_path += ".gz"
        end
        local_path
      end

      def destroy!
        say_status "#{ANSI.red{"Deleting"}} #{remote_path}"
        bucket.object(remote_path).delete unless options.dry_run
      end

      def create!
        say_status "#{ANSI.green{"Creating"}} #{remote_path}#{ gzipped ? ANSI.white {' (gzipped)'} : ''}"
        unless options.dry_run
          upload!
        end
      end

      def upload!
        object = bucket.object(remote_path)
        upload_options = {
          body: local_content,
          content_type: content_type,
          acl: options.acl
        }

        # Add metadata if present
        if local_content_md5
          upload_options[:metadata] = { CONTENT_MD5_KEY => local_content_md5 }
        end

        # Add redirect if present
        upload_options[:website_redirect_location] = redirect_url if redirect?

        # Add content encoding if present
        upload_options[:content_encoding] = "gzip" if options.prefer_gzip && gzipped

        # Add cache control and expires if present
        if caching_policy
          upload_options[:cache_control] = caching_policy.cache_control
          upload_options[:expires] = caching_policy.expires
        end

        # Add storage class if needed
        if options.reduced_redundancy_storage
          upload_options[:storage_class] = 'REDUCED_REDUNDANCY'
        end

        # Add encryption if needed
        if options.encryption
          upload_options[:server_side_encryption] = 'AES256'
        end

        object.put(upload_options)
      end

      def ignore!
        if options.verbose
          reason = if redirect?
                     :redirect
                   elsif directory?
                     :directory
                   end
          say_status "#{ANSI.yellow{"Ignoring"}} #{remote_path} #{ reason ? ANSI.white {"(#{reason})" } : "" }"
        end
      end

      def to_delete?
        status == :deleted
      end

      def to_create?
        status == :new
      end

      def alternate_encoding?
        status == :alternate_encoding
      end

      def identical?
        status == :identical
      end

      def to_update?
        status == :updated
      end

      def to_ignore?
        status == :ignored || status == :alternate_encoding
      end

      def local_content(&block)
        File.open(local_path, &block)
      end

      def status
        @status ||= if shunned?
                      :ignored
                    elsif directory?
                      if remote?
                        :deleted
                      else
                        :ignored
                      end
                    elsif local? && remote?
                      if options.force
                        :updated
                      elsif not metadata_match?
                        :updated
                      elsif local_object_md5 == remote_object_md5
                        :identical
                      else
                        if !gzipped
                          # we're not gzipped, object hashes being different indicates updated content
                          :updated
                        elsif !encoding_match? || local_content_md5 != remote_content_md5
                          # we're gzipped, so we checked the content MD5, and it also changed
                          :updated
                        else
                          # we're gzipped, the object hashes differ, but the content hashes are equal
                          # this means the gzipped bits changed while the original bits did not
                          # what's more, we spent a HEAD request to find out
                          :alternate_encoding
                        end
                      end
                    elsif local?
                      :new
                    elsif remote? && redirect?
                      :ignored
                    elsif remote?
                      :deleted
                    else
                      :ignored
                    end
      end

      def local?
        File.exist?(local_path) && resource
      end

      def remote?
        !full_s3_resource.nil?
      end

      def redirect?
        (resource && resource.redirect?) || (full_s3_resource && full_s3_resource.website_redirect_location)
      end

      def metadata_match?
        redirect_match? && caching_policy_match?
      end

      def redirect_match?
        if redirect?
          redirect_url == remote_redirect_url
        else
          true
        end
      end

      def shunned?
        !!path[Regexp.union(options.ignore_paths)]
      end

      def remote_redirect_url
        full_s3_resource&.website_redirect_location
      end

      def redirect_url
        resource.target_url
      end

      def directory?
        File.directory?(local_path)
      end

      def relative_path
        @relative_path ||= local_path.gsub(/#{build_dir}/, '')
      end

      def remote_object_md5
        s3_resource.etag.gsub(/"/, '') if s3_resource.etag
      end

      def encoding_match?
        (options.prefer_gzip && gzipped && full_s3_resource.content_encoding == 'gzip') || (!options.prefer_gzip && !gzipped && !full_s3_resource.content_encoding )
      end

      def remote_content_md5
        full_s3_resource.metadata[CONTENT_MD5_KEY] if full_s3_resource && full_s3_resource.metadata
      end

      def local_object_md5
        @local_object_md5 ||= Digest::MD5.hexdigest(File.read(local_path))
      end

      def local_content_md5
        @local_content_md5 ||= Digest::MD5.hexdigest(File.read(original_path))
      end

      def original_path
        gzipped ? local_path.gsub(/\.gz$/, '') : local_path
      end

      def content_type
        @content_type ||= Middleman::S3Sync.content_types[local_path]
        @content_type ||= !resource.nil? ? resource.content_type : nil
      end

      def caching_policy
        @caching_policy ||= Middleman::S3Sync.caching_policy_for(content_type)
      end

      def caching_policy_match?
        if (caching_policy)
          caching_policy.cache_control == full_s3_resource.cache_control
        else
          true
        end
      end

      protected
      def bucket
        Middleman::S3Sync.bucket
      end

      def build_dir
        options.build_dir || 'build'
      end

      def options
        @options || Middleman::S3Sync.s3_sync_options
      end
    end
  end
end
