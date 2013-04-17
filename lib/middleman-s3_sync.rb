require 'middleman-core'
require 'fog'
require 'parallel'
require 'digest/md5'
require 'middleman-s3_sync/version'
require 'middleman-s3_sync/commands'

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

        files_to_create.each do |f|
          puts "Creating #{f}"
          file_hash = {
            :key => f,
            :body => File.open(local_path(f)),
            :public => true,
            :acl => 'public-read',
            :content_type => MIME::Types.of(f).first
          }

          # Add cache-control headers
          if policy = options.caching_policy_for(file_hash[:content_type])
            file_hash[:cache_control] = policy.cache_control if policy.cache_control
            file_hash[:expires] = policy.expires if policy.expires
          end

          bucket.files.create(file_hash)
        end

        files_to_update.each do |f|
          puts "Updating #{f}"
          file = s3_files.get(f)
          file.body = File.open(local_path(f))
          file.public = true
          file.content_type = MIME::Types.of(f).first
          if policy = options.caching_policy_for(file.content_type)
            file.cache_control = policy.cache_control if policy.cache_control
            file.expires = policy.expires if policy.expires
          end

          file.save
        end

        files_to_delete.each do |f|
          puts "Deleting #{f}"
          if file = s3_files.get(f)
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

      def remote_files
        @remote_files ||= begin
                            puts "Gathering remote files from #{options.bucket}"
                            bucket.files.map { |f| f.key }
                          end
      end
      def local_files
        @local_files ||= begin
                           puts "Gathering local files."
                           (Dir[build_dir + "/**/*"] + Dir[build_dir + "/**/.*"])
                             .reject { |f| File.directory?(f) }
                             .map { |f| f.gsub(/^#{build_dir}\//, '') }
                         end
      end

      def files_to_delete
        @files_to_delete ||= begin
                               if options.delete
                                 puts "\nDetermine which files to delete from #{options.bucket}"
                                 remote_files - local_files
                               else
                                 []
                               end
                             end
      end

      def files_to_create
        @files_to_create ||= begin
                               puts "Determine files to add to #{options.bucket}."
                               local_files - remote_files
                             end
      end

      def files_to_evaluate
        @files_to_evaluate ||= begin
                                 local_files - files_to_create
                               end
      end

      def files_to_update
        return files_to_evaluate if options.force

        @files_to_update ||= begin
                               puts "Determine which local files to update their S3 counterparts"
                               files_to_update = []
                               Parallel.each(files_to_evaluate, :in_threads => 4) do |f|
                                 print '.'
                                 remote_file = s3_files.get(f)
                                 local_mtime = File.mtime(local_path(f))
                                 remote_mtime = remote_file.last_modified
                                 if remote_mtime < local_mtime
                                   local_md5 = Digest::MD5.hexdigest(File.read(local_path(f)))
                                   remote_md5 = remote_file.etag
                                   files_to_update << f if local_md5 != remote_md5
                                 end
                               end
                               puts ""
                               files_to_update
                             end
      end

      def local_path(f)
        "#{build_dir}/#{f}"
      end

      def build_dir
        @build_dir ||= options.build_dir
      end
    end
  end
end

