module Middleman
  module S3Sync
    class Resource
      attr_accessor :path, :resource, :partial_s3_resource, :full_s3_resource, :content_type, :gzipped, :options


      include Status

      def initialize(resource, partial_s3_resource, path: nil)
        @resource = resource
        @path = if path
                  path.sub(/^\//, '')
                elsif resource
                  resource.destination_path.sub(/^\//, '')
                elsif partial_s3_resource&.key
                  partial_s3_resource.key.sub(/^\//, '')
                else
                  ''
                end
        @partial_s3_resource = partial_s3_resource
      end

      def s3_resource
        @full_s3_resource || @partial_s3_resource
      end

      # S3 resource as returned by a HEAD request
      def full_s3_resource
        @full_s3_resource ||= begin
          bucket.object(remote_path.sub(/^\//, '')).head
        rescue Aws::S3::Errors::NotFound
          nil
        end
      end

      def remote_path
        if s3_resource
          if s3_resource.respond_to?(:key)
            s3_resource.key.sub(/^\//, '')
          else
            # For HeadObjectOutput objects which don't have key method
            options.prefix ? normalize_path(options.prefix, path) : path.sub(/^\//, '')
          end
        else
          options.prefix ? normalize_path(options.prefix, path) : path.sub(/^\//, '')
        end.sub(/^\//, '')  # Ensure no leading slash
      end
      alias :key :remote_path
      
      def normalize_path(prefix, path)
        # Remove any trailing slash from prefix and leading slash from path
        prefix = prefix.chomp('/')
        path = path.sub(/^\//, '')
        "#{prefix}/#{path}"
      end

      def to_h
        attributes = {
          :key => key,
          :content_type => content_type,
          'content-md5' => local_content_md5
        }
        # Only add ACL if enabled (not for buckets with ACLs disabled)
        attributes[:acl] = options.acl if options.acl_enabled?

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
          attributes['website-redirect-location'] = redirect_url
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
        bucket.object(remote_path.sub(/^\//, '')).delete unless options.dry_run
      end

      def create!
        say_status "#{ANSI.green{"Creating"}} #{remote_path}#{ gzipped ? ANSI.white {' (gzipped)'} : ''}"
        unless options.dry_run
          upload!
        end
      end

      def upload!
        object = bucket.object(remote_path.sub(/^\//, ''))
        
        # Use streaming upload for memory efficiency with large files
        File.open(local_path, 'rb') do |file|
          upload_options = build_upload_options_for_stream(file)
          
          begin
            object.put(upload_options)
          rescue Aws::S3::Errors::AccessControlListNotSupported => e
            # Bucket has ACLs disabled - retry without ACL
            if upload_options.key?(:acl)
              say_status "#{ANSI.yellow{"Note"}} Bucket does not support ACLs, retrying without ACL parameter"
              # Automatically disable ACLs for this bucket going forward
              options.acl = ''
              upload_options.delete(:acl)
              file.rewind  # Reset file position for retry
              retry
            else
              raise e
            end
          end
        end
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

      def local_content
        if block_given?
          File.open(local_path) { |f| yield f.read }
        else
          File.read(local_path)
        end
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
        # For orphan files (scan_build_dir), resource is nil but file exists
        File.exist?(local_path)
      end

      def remote?
        !full_s3_resource.nil?
      end

      def redirect?
        !!(resource && resource.respond_to?(:redirect?) && resource.redirect?) || 
          !!(full_s3_resource && full_s3_resource.respond_to?(:website_redirect_location) && full_s3_resource.website_redirect_location)
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
        resource.respond_to?(:target_url) ? resource.target_url : nil
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
        if full_s3_resource && full_s3_resource.metadata
          full_s3_resource.metadata['content-md5']
        end
      end

      def local_object_md5
        @local_object_md5 ||= begin
          # When not gzipped, compute both MD5s in single read to avoid redundant I/O
          if !gzipped && local_path == original_path
            compute_md5s_single_read
            @local_object_md5
          else
            Digest::MD5.hexdigest(File.read(local_path))
          end
        end
      end

      def local_content_md5
        @local_content_md5 ||= begin
          # When not gzipped, compute both MD5s in single read to avoid redundant I/O
          if !gzipped && local_path == original_path
            compute_md5s_single_read
            @local_content_md5
          elsif File.exist?(original_path)
            Digest::MD5.hexdigest(File.read(original_path))
          else
            nil
          end
        end
      end

      # Compute both MD5s from a single file read when they're the same file
      def compute_md5s_single_read
        return if @md5s_computed
        content = File.read(local_path)
        md5 = Digest::MD5.hexdigest(content)
        @local_object_md5 = md5
        @local_content_md5 = md5
        @md5s_computed = true
      end

      def original_path
        gzipped ? local_path.gsub(/\.gz$/, '') : local_path
      end

      def content_type
        @content_type ||= begin
          # Priority: content_types option > mm_resource > mime-types > default
          ct = options.content_types[local_path] if options.content_types
          ct ||= options.content_types[path] if options.content_types
          ct ||= Middleman::S3Sync.content_types[local_path]
          ct ||= Middleman::S3Sync.content_types[path]
          ct ||= resource.content_type if resource&.respond_to?(:content_type)
          ct ||= detect_content_type_from_extension
          ct || 'application/octet-stream'
        end
      end

      def detect_content_type_from_extension
        return nil unless defined?(MIME::Types)
        extension = File.extname(original_path).delete_prefix('.')
        return nil if extension.empty?
        types = MIME::Types.type_for(extension)
        types.first&.content_type
      end

      def caching_policy
        @caching_policy ||= Middleman::S3Sync.caching_policy_for(content_type)
      end

      def caching_policy_match?
        if caching_policy && full_s3_resource && full_s3_resource.respond_to?(:cache_control)
          caching_policy.cache_control == full_s3_resource.cache_control
        else
          true
        end
      end

      protected
      
      # Build upload options with a file stream as the body
      def build_upload_options_for_stream(file_stream)
        upload_options = {
          body: file_stream,
          content_type: content_type
        }
        # Only add ACL if enabled (not for buckets with ACLs disabled)
        upload_options[:acl] = options.acl if options.acl_enabled?

        # Add metadata if present
        if local_content_md5
          upload_options[:metadata] = { 'content-md5' => local_content_md5 }
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

        upload_options
      end

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
