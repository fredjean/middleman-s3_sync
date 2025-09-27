require 'aws-sdk-s3'
require 'digest/md5'
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

module Middleman
  module S3Sync
    class << self
      include Status
      include CachingPolicy

      @@bucket_lock = Mutex.new
      @@bucket_files_lock = Mutex.new

      attr_accessor :s3_sync_options
      attr_accessor :mm_resources
      attr_reader   :app

      THREADS_COUNT = 8
      
      # Track paths that were changed during sync for CloudFront invalidation
      attr_accessor :invalidation_paths

      def sync()
        @app ||= ::Middleman::Application.new
        @invalidation_paths = []

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
          CloudFront.invalidate(@invalidation_paths, s3_sync_options)
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
        @invalidation_paths ||= []
        # Normalize path for CloudFront (ensure it starts with /)
        normalized_path = path.start_with?('/') ? path : "/#{path}"
        @invalidation_paths << normalized_path unless @invalidation_paths.include?(normalized_path)
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

        if opts[:error_document] && !opts[:index_document]
          raise 'S3 requires `index_document` if `error_document` is specified'
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
        Parallel.map(files_to_delete, in_threads: THREADS_COUNT) do |resource|
          resource.destroy!
          add_invalidation_path(resource.path)
        end
      end

      def ignore_resources
        Parallel.map(files_to_ignore, in_threads: THREADS_COUNT, &:ignore!)
      end

      def work_to_be_done?
        Parallel.each(mm_resources, in_threads: THREADS_COUNT, progress: "Processing sitemap") { |mm_resource| add_local_resource(mm_resource) }

        Parallel.each(remote_only_paths, in_threads: THREADS_COUNT, progress: "Processing remote files") do |remote_path|
          s3_sync_resources[remote_path] ||= S3Sync::Resource.new(nil, remote_resource_for_path(remote_path)).tap(&:status)
        end

        !(files_to_create.empty? && files_to_update.empty? && files_to_delete.empty?)
      end

      def files_to_delete
        if s3_sync_options.delete
          s3_sync_resources.values.select { |r| r.to_delete? }
        else
          []
        end
      end

      def files_to_create
        s3_sync_resources.values.select { |r| r.to_create? }
      end

      def files_to_update
        s3_sync_resources.values.select { |r| r.to_update? }
      end

      def files_to_ignore
        s3_sync_resources.values.select { |r| r.to_ignore? }
      end

      def build_dir
        @build_dir ||= s3_sync_options.build_dir
      end
    end
  end
end
