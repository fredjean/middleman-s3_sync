require 'fog/aws'
require 'fog/aws/storage'
require 'digest/md5'
require 'middleman/s3_sync/version'
require 'middleman/s3_sync/options'
require 'middleman/s3_sync/caching_policy'
require 'middleman/s3_sync/status'
require 'middleman/s3_sync/resource'
require 'middleman-s3_sync/extension'
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

      def sync()
        say_status "Let's see if there's work to be done..."
        unless work_to_be_done?
          say_status "All S3 files are up to date."
          return
        end

        say_status "Ready to apply updates to #{s3_sync_options.bucket}."

        update_bucket_versioning

        update_bucket_website

        ignore_resources
        create_resources
        update_resources
        delete_resources

        app.run_hook :after_s3_sync, ignored: files_to_ignore.map(&:path),
                                      created: files_to_create.map(&:path),
                                      updated: files_to_update.map(&:path),
                                      deleted: files_to_delete.map(&:path)
      end

      def bucket
        @@bucket_lock.synchronize do
          @bucket ||= begin
                        bucket = connection.directories.get(s3_sync_options.bucket, :prefix => s3_sync_options.prefix)
                        raise "Bucket #{s3_sync_options.bucket} doesn't exist!" unless bucket
                        bucket
                      end
        end
      end

      def add_local_resource(mm_resource)
        s3_sync_resources[mm_resource.destination_path] = S3Sync::Resource.new(mm_resource, remote_resource_for_path(mm_resource.destination_path)).tap(&:status)
      end

      def remote_only_paths
        paths - s3_sync_resources.keys
      end

      def app=(app)
        @app = app
        @app.extend ::Middleman::S3SyncExtension::ClassMethods
      end

      def content_types
        @content_types || {}
      end

      protected
      def update_bucket_versioning
        connection.put_bucket_versioning(s3_sync_options.bucket, "Enabled") if s3_sync_options.version_bucket
      end

      def update_bucket_website
        opts = {}
        opts[:IndexDocument] = s3_sync_options.index_document if s3_sync_options.index_document
        opts[:ErrorDocument] = s3_sync_options.error_document if s3_sync_options.error_document

        if opts[:ErrorDocument] && !opts[:IndexDocument]
          raise 'S3 requires `index_document` if `error_document` is specified'
        end

        unless opts.empty?
          say_status "Putting bucket website: #{opts.to_json}"
          connection.put_bucket_website(s3_sync_options.bucket, opts)
        end
      end

      def connection
        connection_options = {
          :region => s3_sync_options.region,
          :path_style => s3_sync_options.path_style
        }

        if s3_sync_options.aws_access_key_id && s3_sync_options.aws_secret_access_key
          connection_options.merge!({
            :aws_access_key_id => s3_sync_options.aws_access_key_id,
            :aws_secret_access_key => s3_sync_options.aws_secret_access_key
          })
        else
          connection_options.merge!({ :use_iam_profile => true })
        end

        @connection ||= Fog::Storage::AWS.new(connection_options)
      end

      def remote_resource_for_path(path)
        bucket_files.find { |f| f.key == "#{s3_sync_options.prefix}#{path}" }
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
                            bucket_files.map(&:key)
                          else
                            []
                          end
      end

      def bucket_files
        @@bucket_files_lock.synchronize do
          @bucket_files ||= [].tap { |files|
            bucket.files.each { |f|
              files << f
            }
          }
        end
      end

      def create_resources
        files_to_create.each do |r|
          r.create!
        end
      end

      def update_resources
        files_to_update.each do |r|
          r.update!
        end
      end

      def delete_resources
        files_to_delete.each do |r|
          r.destroy!
        end
      end

      def ignore_resources
        files_to_ignore.each do |r|
          r.ignore!
        end
      end

      def work_to_be_done?
        Parallel.each(mm_resources, in_threads: 8, progress: "Processing sitemap") { |mm_resource| add_local_resource(mm_resource) }

        Parallel.each(remote_only_paths, in_threads: 8, progress: "Processing remote files") do |remote_path|
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
