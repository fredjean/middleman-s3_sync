require 'fog/aws/storage'
require 'pmap'
require 'digest/md5'
require 'middleman/s3_sync/version'
require 'middleman/s3_sync/options'
require 'middleman-s3_sync/commands'
require 'middleman/s3_sync/status'
require 'middleman/s3_sync/resource'
require 'middleman-s3_sync/extension'
require 'ruby-progressbar'
require 'thread'

module Middleman
  module S3Sync
    class << self
      include Status
      @@bucket_lock = Mutex.new
      @@bucket_files_lock = Mutex.new

      attr_accessor :s3_sync_options

      def sync(options)
        @app = ::Middleman::Application.server.inst

        self.s3_sync_options = options

        unless work_to_be_done?
          say_status "\nAll S3 files are up to date."
          return
        end

        say_status "\nReady to apply updates to #{s3_sync_options.bucket}."

        update_bucket_versioning

        ignore_resources
        create_resources
        update_resources
        delete_resources

        @app.run_hook :after_s3_sync, ignored: files_to_ignore.map(&:path),
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
        resources[mm_resource.path] = S3Sync::Resource.new(mm_resource, remote_resource_for_path(mm_resource.path)).tap(&:status)
      end

      protected
      def update_bucket_versioning
        connection.put_bucket_versioning(s3_sync_options.bucket, "Enabled") if s3_sync_options.version_bucket
      end

      def connection
        @connection ||= Fog::Storage::AWS.new({
          :aws_access_key_id => s3_sync_options.aws_access_key_id,
          :aws_secret_access_key => s3_sync_options.aws_secret_access_key,
          :region => s3_sync_options.region,
          :path_style => s3_sync_options.path_style
        })
      end

      def remote_resource_for_path(path)
        bucket_files.find { |f| f.key == "#{s3_sync_option.prefix}#{path}" }
      end

      def resources
        @resource ||= {}
      end

      def progress_bar
        @progress_bar ||= ProgressBar.create(total: paths.length)
      end

      def paths
        @paths ||= begin
                     say_status "Gathering the paths to evaluate."
                     (remote_paths.map { |rp| rp.gsub(/^#{s3_sync_options.prefix}/, '')} + local_paths).uniq.sort
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
        !(files_to_create.empty? && files_to_update.empty? && files_to_delete.empty?)
      end

      def files_to_delete
        @files_to_delete ||= if s3_sync_options.delete
                                 resources.select { |r| r.to_delete? }
                             else
                               []
                             end
      end

      def files_to_create
        @files_to_create ||= resources.select { |r| r.to_create? }
      end

      def files_to_update
        @files_to_update ||= resources.select { |r| r.to_update? }
      end

      def files_to_ignore
        @files_to_ignore ||= resources.select { |r| r.to_ignore? }
      end

      def build_dir
        @build_dir ||= s3_sync_options.build_dir
      end
    end
  end
end

