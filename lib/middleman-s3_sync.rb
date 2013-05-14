require 'middleman-core'
require 'fog'
require 'pmap'
require 'ruby-progressbar'
require 'digest/md5'
require 'middleman-s3_sync/version'
require 'middleman-s3_sync/commands'
require 'middleman/s3_sync/resource'

Fog::Logger[:warning] = nil

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

        puts "\nReady to apply updates to #{s3_sync_options.bucket}."

        create_resources
        update_resources
        delete_resources
      end

      def bucket
        @bucket ||= connection.directories.get(s3_sync_options.bucket)
      end

      protected
      def connection
        @connection ||= Fog::Storage.new({
          :provider => 'AWS',
          :aws_access_key_id => s3_sync_options.aws_access_key_id,
          :aws_secret_access_key => s3_sync_options.aws_secret_access_key,
          :region => s3_sync_options.region
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
                     (remote_paths + local_paths).uniq.sort
                   end
      end

      def local_paths
        @local_paths ||= begin
                           local_paths = (Dir[build_dir + "/**/*"] + Dir[build_dir + "/**/.*"])
                                           .reject { |p| File.directory?(p) }

                           if s3_sync_options.prefer_gzip
                             local_paths.reject! { |p| p =~ /\.gz$/ && File.exist?(p.gsub(/\.gz$/, '')) }
                           end

                           local_paths.pmap { |p| p.gsub(/#{build_dir}\//, '') }
                         end
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
        return resources.select { |r| r.local? } if s3_sync_options.force

        @files_to_update ||= resources.select { |r| r.to_update? }
      end

      def build_dir
        @build_dir ||= s3_sync_options.build_dir
      end
    end
  end
end

