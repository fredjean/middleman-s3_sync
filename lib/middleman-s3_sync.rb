require "middleman-core"
require "fog"
require 'digest/md5'
require "middleman-s3_sync/version"
require "middleman-s3_sync/commands"

::Middleman::Extensions.register(:s3_sync, '>= 3.0.0') do
  require 'middleman-s3_sync/extension'
  ::Middleman::S3Sync
end

module Middleman
  module S3Sync
    class << self
      def sync
        puts "Determine which files to upload..."
        local_files = Dir[options.public_path + "/**/*"]
          .reject { |f| File.directory?(f) }
          .map { |f| f.gsub(/^build\//, '') }
        remote_files = bucket.files.map { |f| f.key }

        # First pass on the set of files to work with.
        files_to_push = local_files - remote_files
        files_to_delete = remote_files - local_files
        files_to_evaluate = local_files - files_to_push

        # No need to evaluate the files that are newer on S3 than the local files.
        files_to_evaluate.reject! do |f|
          local_mtime = File.mtime("build/#{f}")
          remote_mtime = s3_files.get(f).last_modified
          remote_mtime >= local_mtime
        end

        # Are the files different? Use MD5 to see
        files_to_evaluate.each do |f|
          local_md5 = Digest::MD5.hexdigest(File.read("build/#{f}"))
          remote_md5 = s3_files.get(f).etag
          files_to_push << f if local_md5 != remote_md5
        end

        files_to_push.each do |f|
          if remote_files.include?(f)
            puts "Updating #{f}"
            file = s3_files.get(f)
            file.body = File.open("build/#{f}")
            file.save
          else
            puts "Creating #{f}"
            file = bucket.files.create({
              :key => f,
              :body => File.open("build/#{f}"),
              :public => true
            })
          end
        end

        if options.delete
          files_to_delete.each do |f|
            puts "Deleting #{f}"
            file = s3_files.get(f)
            file.destroy
          end
        end
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

      def bucket
        @bucket ||= connection.directories.get(options.bucket)
      end

      def s3_files
        @s3_files ||= bucket.files
      end
    end
  end
end

