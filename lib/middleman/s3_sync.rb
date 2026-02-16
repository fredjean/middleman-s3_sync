require 'aws-sdk-s3'
require 'digest/md5'
require 'mime/types'
require 'middleman/s3_sync/version'
require 'middleman/s3_sync/options'
require 'middleman/s3_sync/caching_policy'
require 'middleman/s3_sync/status'
require 'middleman/s3_sync/resource'
require 'middleman/s3_sync/cloudfront'
require 'middleman-s3_sync/extension'
require 'middleman/redirect'
require 'parallel'
require 'ruby-progressbar'
require 'thread'
require 'set'

module Middleman
  module S3Sync
    class << self
      include Status
      include CachingPolicy

      @@bucket_lock = Mutex.new
      @@bucket_files_lock = Mutex.new
      @@invalidation_paths_lock = Mutex.new

      attr_accessor :s3_sync_options
      attr_accessor :mm_resources
      attr_reader   :app

      THREADS_COUNT = 8
      
      # Track paths that were changed during sync for CloudFront invalidation
      # Using a Set for O(1) lookups
      attr_reader :invalidation_paths

      def sync()
        @app ||= ::Middleman::Application.new
        @invalidation_paths = Set.new

        # Ensure sitemap is fully populated before syncing
        # This catches resources from extensions activated in :build mode
        if @app.respond_to?(:sitemap) && @app.sitemap.respond_to?(:ensure_resource_list_updated!)
          @app.sitemap.ensure_resource_list_updated!
        end

        say_status "Let's see if there's work to be done..."
        unless work_to_be_done?
          say_status "All S3 files are up to date."
          
          # Still run CloudFront invalidation if requested for all paths
          if s3_sync_options.cloudfront_invalidate && s3_sync_options.cloudfront_invalidate_all
            CloudFront.invalidate([], s3_sync_options)
          end
          return
        end

        say_status "Ready to apply updates to #{s3_sync_options.bucket}."

        update_bucket_versioning

        update_bucket_website

        ignore_resources
        create_resources
        update_resources
        delete_resources
        
        # Invalidate CloudFront cache if requested
        if s3_sync_options.cloudfront_invalidate
          CloudFront.invalidate(@invalidation_paths.to_a, s3_sync_options)
        end
      end

      def bucket
        @@bucket_lock.synchronize do
          @bucket ||= begin
                        bucket = s3_resource.bucket(s3_sync_options.bucket)
                        raise "Bucket #{s3_sync_options.bucket} doesn't exist!" unless bucket.exists?
                        bucket
                      end
        end
      end

      def add_local_resource(mm_resource)
        s3_sync_resources[mm_resource.destination_path] = S3Sync::Resource.new(mm_resource, remote_resource_for_path(mm_resource.destination_path)).tap(&:status)
      end
      
      def add_invalidation_path(path)
        @@invalidation_paths_lock.synchronize do
          @invalidation_paths ||= Set.new
          # Normalize path for CloudFront (ensure it starts with /)
          normalized_path = path.start_with?('/') ? path : "/#{path}"
          @invalidation_paths.add(normalized_path)
        end
      end

      def remote_only_paths
        paths - s3_sync_resources.keys
      end

      def app=(app)
        @app = app
      end

      def content_types
        @content_types || {}
      end

      protected
      def update_bucket_versioning
        s3_client.put_bucket_versioning({
          bucket: s3_sync_options.bucket,
          versioning_configuration: {
            status: "Enabled"
          }
        }) if s3_sync_options.version_bucket
      end

      def update_bucket_website
        opts = {}
        opts[:index_document] = { suffix: s3_sync_options.index_document } if s3_sync_options.index_document
        opts[:error_document] = { key: s3_sync_options.error_document } if s3_sync_options.error_document

        # Add routing rules if specified
        if s3_sync_options.routing_rules && !s3_sync_options.routing_rules.empty?
          opts[:routing_rules] = s3_sync_options.routing_rules.map do |rule|
            routing_rule = {}
            
            # Handle condition (optional)
            if rule[:condition] || rule['condition']
              condition = rule[:condition] || rule['condition']
              routing_rule[:condition] = {}
              routing_rule[:condition][:key_prefix_equals] = condition[:key_prefix_equals] || condition['key_prefix_equals'] if condition[:key_prefix_equals] || condition['key_prefix_equals']
              routing_rule[:condition][:http_error_code_returned_equals] = condition[:http_error_code_returned_equals] || condition['http_error_code_returned_equals'] if condition[:http_error_code_returned_equals] || condition['http_error_code_returned_equals']
            end
            
            # Handle redirect (required)
            redirect = rule[:redirect] || rule['redirect']
            routing_rule[:redirect] = {}
            routing_rule[:redirect][:host_name] = redirect[:host_name] || redirect['host_name'] if redirect[:host_name] || redirect['host_name']
            routing_rule[:redirect][:http_redirect_code] = redirect[:http_redirect_code] || redirect['http_redirect_code'] if redirect[:http_redirect_code] || redirect['http_redirect_code']
            routing_rule[:redirect][:protocol] = redirect[:protocol] || redirect['protocol'] if redirect[:protocol] || redirect['protocol']
            routing_rule[:redirect][:replace_key_prefix_with] = redirect[:replace_key_prefix_with] || redirect['replace_key_prefix_with'] if redirect[:replace_key_prefix_with] || redirect['replace_key_prefix_with']
            routing_rule[:redirect][:replace_key_with] = redirect[:replace_key_with] || redirect['replace_key_with'] if redirect[:replace_key_with] || redirect['replace_key_with']
            
            routing_rule
          end
        end

        if opts[:error_document] && !opts[:index_document]
          raise 'S3 requires `index_document` if `error_document` is specified'
        end

        # S3 requires index_document if routing_rules are specified
        if opts[:routing_rules] && !opts[:index_document]
          raise 'S3 requires `index_document` if `routing_rules` are specified'
        end

        unless opts.empty?
          say_status "Putting bucket website: #{opts.to_json}"
          s3_client.put_bucket_website({
            bucket: s3_sync_options.bucket,
            website_configuration: opts
          })
        end
      end

      def s3_client
        @s3_client ||= Aws::S3::Client.new(connection_options)
      end

      def s3_resource
        @s3_resource ||= Aws::S3::Resource.new(client: s3_client)
      end

      def connection_options
        @connection_options ||= begin
          connection_options = {
            endpoint: s3_sync_options.endpoint,
            region: s3_sync_options.region,
            force_path_style: s3_sync_options.path_style
          }

          if s3_sync_options.aws_access_key_id && s3_sync_options.aws_secret_access_key
            connection_options.merge!({
              access_key_id: s3_sync_options.aws_access_key_id,
              secret_access_key: s3_sync_options.aws_secret_access_key
            })

            # If using an assumed role
            connection_options.merge!({
              session_token: s3_sync_options.aws_session_token
            }) if s3_sync_options.aws_session_token
          end

          connection_options
        end
      end

      def remote_resource_for_path(path)
        bucket_files[path]
      end

      def s3_sync_resources
        @s3_sync_resources ||= {}
      end

      def paths
        @paths ||= begin
                     (remote_paths.map { |rp| rp.gsub(/^#{s3_sync_options.prefix}/, '')} + s3_sync_resources.keys).uniq.sort
                   end
      end

      def remote_paths
        @remote_paths ||= if s3_sync_options.delete
                            bucket_files.keys
                          else
                            []
                          end
      end

      def bucket_files
        @@bucket_files_lock.synchronize do
          @bucket_files ||= begin
            files = {}
            bucket.objects.each do |object|
              files[object.key] = object
            end
            files
          end
        end
      end

      def create_resources
        Parallel.map(files_to_create, in_threads: THREADS_COUNT) do |resource|
          resource.create!
          add_invalidation_path(resource.path)
        end
      end

      def update_resources
        Parallel.map(files_to_update, in_threads: THREADS_COUNT) do |resource|
          resource.update!
          add_invalidation_path(resource.path)
        end
      end

      def delete_resources
        resources = files_to_delete
        return if resources.empty?

        # Print status messages for all resources being deleted
        resources.each do |resource|
          say_status "#{ANSI.red{"Deleting"}} #{resource.remote_path}"
          add_invalidation_path(resource.path)
        end

        # Batch delete using S3's delete_objects API (up to 1000 objects per request)
        unless s3_sync_options.dry_run
          resources.each_slice(1000) do |batch|
            objects_to_delete = batch.map { |r| { key: r.remote_path.sub(/^\//, '') } }
            bucket.delete_objects(delete: { objects: objects_to_delete })
          end
        end
      end

      def ignore_resources
        Parallel.map(files_to_ignore, in_threads: THREADS_COUNT, &:ignore!)
      end

      def work_to_be_done?
        Parallel.each(mm_resources, in_threads: THREADS_COUNT, progress: "Processing sitemap") { |mm_resource| add_local_resource(mm_resource) }

        # Scan build directory for orphan files (not in sitemap)
        if s3_sync_options.scan_build_dir
          discover_orphan_files
        end

        Parallel.each(remote_only_paths, in_threads: THREADS_COUNT, progress: "Processing remote files") do |remote_path|
          s3_sync_resources[remote_path] ||= S3Sync::Resource.new(nil, remote_resource_for_path(remote_path)).tap(&:status)
        end

        !(files_to_create.empty? && files_to_update.empty? && files_to_delete.empty?)
      end

      # Discover files in build directory that are not in the sitemap
      # This handles files generated by after_build callbacks, image optimizers, etc.
      def discover_orphan_files
        return unless build_dir && File.directory?(build_dir)

        orphan_files = []
        
        Dir.glob(File.join(build_dir, '**', '*')).each do |file_path|
          next if File.directory?(file_path)
          
          # Get path relative to build_dir
          relative_path = file_path.sub(/^#{Regexp.escape(build_dir)}\/?/, '')
          
          # Skip if already in sitemap resources
          next if s3_sync_resources.key?(relative_path)
          
          orphan_files << relative_path
        end

        return if orphan_files.empty?

        say_status "Found #{orphan_files.size} files outside sitemap"
        
        Parallel.each(orphan_files, in_threads: THREADS_COUNT, progress: "Processing orphan files") do |relative_path|
          # Create a Resource with nil mm_resource but explicit path
          # It will use mime-types for content type detection
          remote = remote_resource_for_path(relative_path)
          resource = S3Sync::Resource.new(nil, remote, path: relative_path)
          s3_sync_resources[relative_path] = resource.tap(&:status)
        end
      end

      # Single-pass categorization of resources by status
      # Avoids multiple iterations over s3_sync_resources
      def categorized_resources
        @categorized_resources ||= begin
          result = { create: [], update: [], delete: [], ignore: [] }
          s3_sync_resources.values.each do |resource|
            case
            when resource.to_create? then result[:create] << resource
            when resource.to_update? then result[:update] << resource
            when resource.to_delete? then result[:delete] << resource
            when resource.to_ignore? then result[:ignore] << resource
            end
          end
          result
        end
      end

      def files_to_delete
        if s3_sync_options.delete
          categorized_resources[:delete]
        else
          []
        end
      end

      def files_to_create
        categorized_resources[:create]
      end

      def files_to_update
        categorized_resources[:update]
      end

      def files_to_ignore
        categorized_resources[:ignore]
      end

      def build_dir
        @build_dir ||= s3_sync_options.build_dir
      end
    end
  end
end
