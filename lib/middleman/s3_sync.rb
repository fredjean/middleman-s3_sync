require 'fog'
require 'pmap'
require 'digest/md5'
require 'middleman/s3_sync/version'
require 'middleman/s3_sync/options'
require 'middleman-s3_sync/commands'
require 'middleman/s3_sync/status'
require 'middleman/s3_sync/resource'
require 'middleman-s3_sync/extension'
require 'ruby-progressbar'

module Middleman
  module S3Sync
    class << self
      include Status

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
        @bucket ||= begin
                      bucket = connection.directories.get(s3_sync_options.bucket, :prefix => s3_sync_options.prefix)
                      raise "Bucket #{s3_sync_options.bucket} doesn't exist!" unless bucket
                      bucket
                    end
      end

      protected
      def update_bucket_versioning
        connection.put_bucket_versioning(s3_sync_options.bucket, "Enabled") if s3_sync_options.version_bucket
      end

      def connection
        @connection ||= Fog::Storage.new({
          :provider => 'AWS',
          :aws_access_key_id => s3_sync_options.aws_access_key_id,
          :aws_secret_access_key => s3_sync_options.aws_secret_access_key,
          :region => s3_sync_options.region,
          :path_style => s3_sync_options.path_style
        })
      end

      def resources
        @resources ||= paths.pmap(32) do |p|
          progress_bar.increment
          S3Sync::Resource.new(p, bucket_files.find { |f| f.key == "#{s3_sync_options.prefix}#{p}" }).tap(&:status)
        end
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

      def local_paths
        @local_paths ||= begin
                           local_paths = (Dir[build_dir + "/**/*"] + Dir[build_dir + "/**/.*"])
                                           .reject { |p| File.directory?(p) }

                           if s3_sync_options.prefer_gzip
                             local_paths.reject! { |p| p =~ /\.gz$/ && File.exist?(p.gsub(/\.gz$/, '')) }
                           end

                           local_paths.pmap(32) { |p| p.gsub(/#{build_dir}\//, '') }
                         end
      end

      def remote_paths
        @remote_paths ||= bucket_files.map(&:key)
      end

      def bucket_files
        @bucket_files ||= [].tap { |files|
          bucket.files.each { |f|
            files << f
          }
        }
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

