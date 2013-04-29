require 'middleman-core'
require 'fog'
require 'pmap'
require 'ruby-progressbar'
require 'digest/md5'
require 'middleman-s3_sync/version'
require 'middleman-s3_sync/commands'
require 'middleman/s3_sync/resource'

::Middleman::Extensions.register(:s3_sync, '>= 3.0.0') do
  require 'middleman-s3_sync/extension'
  ::Middleman::S3Sync
end

module Middleman
  module S3Sync
    class << self
      def sync
        unless work_to_be_done?
          puts "\nAll S3 files are up to date."
          return
        end

        puts "\nReady to apply updates to #{options.bucket}."

        create_resources
        update_resources
        delete_resources
      end

      def bucket
        @bucket ||= connection.directories.get(options.bucket)
      end

      protected
      def connection
        @connection ||= Fog::Storage.new({
          :provider => 'AWS',
          :aws_access_key_id => options.aws_access_key_id,
          :aws_secret_access_key => options.aws_secret_access_key,
          :region => options.region
        })
      end

      def resources
        @resources ||= paths.pmap do |p|
          progress_bar.increment
          S3Sync::Resource.new(p)
        end
      end

      def progress_bar
        @progress_bar ||= ProgressBar.create(total: paths.length)
      end

      def paths
        @paths ||= begin
                     puts "Gathering the paths to evaluate."
                     (local_paths + remote_paths).uniq.sort
                   end
      end

      def local_paths
        @local_paths ||= (Dir[build_dir + "/**/*"] + Dir[build_dir + "/**/.*"])
          .reject { |p| File.directory?(p) }
          .pmap { |p| p.gsub(/#{build_dir}\//, '') }
      end

      def remote_paths
        @remote_paths ||= bucket.files.map{ |f| f.key }
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

      def work_to_be_done?
        !(files_to_create.empty? && files_to_update.empty? && files_to_delete.empty?)
      end

      def files_to_delete
        @files_to_delete ||= if options.delete
                                 resources.select { |r| r.to_delete? }
                             else
                               []
                             end
      end

      def files_to_create
        @files_to_create ||= resources.select { |r| r.to_create? }
      end

      def files_to_update
        return resources.select { |r| r.local? } if options.force

        @files_to_update ||= resources.select { |r| r.to_update? }
      end

      def build_dir
        @build_dir ||= options.build_dir
      end
    end
  end
end

