require 'middleman-core'
require 'fog'
require 'pmap'
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
        if files_to_create.empty? && files_to_update.empty? && files_to_delete.empty?
          puts "\nAll S3 files are up to date."
          return
        end

        puts "\nReady to apply updates to #{options.bucket}."

        files_to_create.each do |r|
          r.create!
        end

        files_to_update.each do |r|
          r.update!
        end

        files_to_delete.each do |r|
          r.destroy!
        end
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
          print '.'
          S3Sync::Resource.new(p)
        end
      end

      def paths
        @paths ||= begin
                     puts "Gathering the paths to evaluate."
                     local_paths = (Dir[build_dir + "/**/*"] + Dir[build_dir + "/**/.*"])
                       .reject { |p| File.directory?(p) }
                       .pmap { |p| p.gsub(/#{build_dir}\//, '') }
                     remote_paths = bucket.files.map { |f| f.key }

                     (local_paths + remote_paths).uniq.sort
                   end
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

