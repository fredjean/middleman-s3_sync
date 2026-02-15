require 'aws-sdk-cloudfront'
require 'securerandom'
require 'set'

module Middleman
  module S3Sync
    module CloudFront
      class << self
        include Status

        def invalidate(invalidation_paths, options)
          return unless should_invalidate?(options)
          return if invalidation_paths.empty? && !options.cloudfront_invalidate_all

          paths = prepare_invalidation_paths(invalidation_paths, options)
          return if paths.empty?

          say_status "Invalidating CloudFront distribution #{options.cloudfront_distribution_id}"
          
          if options.dry_run
            say_status "#{ANSI.yellow{'DRY RUN:'}} Would invalidate #{paths.length} paths in CloudFront"
            paths.each { |path| say_status "  #{path}" } if options.verbose
            return
          end

          # Split paths into batches to respect CloudFront limits
          batch_size = [options.cloudfront_invalidation_batch_size, 3000].min
          path_batches = paths.each_slice(batch_size).to_a

          invalidation_ids = []
          
          path_batches.each_with_index do |batch, index|
            say_status "Creating invalidation batch #{index + 1}/#{path_batches.length} (#{batch.length} paths)"
            
            invalidation_id = create_invalidation_with_retry(batch, options)
            invalidation_ids << invalidation_id if invalidation_id
            
            # Add a delay between batches to avoid rate limiting
            delay = options.cloudfront_invalidation_batch_delay || 2
            sleep(delay) if path_batches.length > 1 && index < path_batches.length - 1
          end

          if invalidation_ids.any?
            say_status "CloudFront invalidation(s) created: #{invalidation_ids.join(', ')}"
            
            if options.cloudfront_wait
              say_status "Waiting for CloudFront invalidation(s) to complete..."
              wait_for_invalidations(invalidation_ids, options)
              say_status "CloudFront invalidation(s) completed successfully"
            else
              say_status "Invalidations may take 10-15 minutes to complete"
            end
          end

          invalidation_ids
        rescue Aws::CloudFront::Errors::ServiceError => e
          say_status "#{ANSI.red{'CloudFront invalidation failed:'}} #{e.message}"
          raise e unless options.verbose # Re-raise unless we're being verbose
        end

        private

        def should_invalidate?(options)
          return false unless options.cloudfront_invalidate
          
          unless options.cloudfront_distribution_id
            say_status "#{ANSI.yellow{'CloudFront invalidation skipped:'}} no distribution ID provided"
            return false
          end

          true
        end

        def prepare_invalidation_paths(invalidation_paths, options)
          if options.cloudfront_invalidate_all
            return ['/*']
          end

          # Normalize paths for CloudFront
          paths = invalidation_paths.map do |path|
            # Ensure path starts with /
            normalized_path = path.start_with?('/') ? path : "/#{path}"
            
            # Remove any double slashes
            normalized_path.gsub(/\/+/, '/')
          end.uniq.sort

          # Remove any paths that would be covered by a wildcard
          if paths.include?('/*')
            paths = ['/*']
          else
            # Remove redundant paths (e.g., if we have /path/* and /path/file.html)
            paths = remove_redundant_paths(paths)
          end

          say_status "Prepared #{paths.length} paths for CloudFront invalidation" if options.verbose

          paths
        end

        def remove_redundant_paths(paths)
          # Sort paths to ensure wildcards come before specific files
          sorted_paths = paths.sort
          result = []
          # Use a Set for O(1) lookup of wildcard prefixes
          wildcard_prefixes = Set.new
          
          sorted_paths.each do |path|
            # Check if this path is covered by any existing wildcard prefix
            # by checking all parent directories of this path
            is_redundant = path_covered_by_wildcard?(path, wildcard_prefixes)
            
            unless is_redundant
              result << path
              # If this is a wildcard path, add its prefix for future lookups
              if path.end_with?('/*')
                wildcard_prefixes.add(path[0..-3]) # Remove /*
              end
            end
          end
          
          result
        end

        # Check if a path is covered by any wildcard prefix in O(path_depth) time
        def path_covered_by_wildcard?(path, wildcard_prefixes)
          return false if wildcard_prefixes.empty?
          
          # Check each parent directory of the path
          segments = path.split('/')
          current_path = ''
          
          segments[0..-2].each do |segment|  # Exclude the last segment
            current_path = current_path.empty? ? segment : "#{current_path}/#{segment}"
            return true if wildcard_prefixes.include?(current_path)
          end
          
          false
        end

        def create_invalidation_with_retry(paths, options)
          max_retries = options.cloudfront_invalidation_max_retries || 5
          retries = 0
          base_delay = 1
          
          begin
            create_invalidation(paths, options)
          rescue Aws::CloudFront::Errors::ServiceError => e
            if (e.message.include?('Rate exceeded') || e.message.include?('Throttling')) && retries < max_retries
              retries += 1
              delay = base_delay * (2 ** (retries - 1)) + rand(1..3) # Exponential backoff with jitter
              say_status "#{ANSI.yellow{"Rate limit hit, retrying in #{delay} seconds..."}} (attempt #{retries}/#{max_retries})"
              sleep(delay)
              retry
            else
              say_status "#{ANSI.red{'Failed to create CloudFront invalidation:'}} #{e.message}"
              say_status "Paths: #{paths.join(', ')}" if options.verbose
              raise e unless options.verbose
              nil
            end
          end
        end

        def create_invalidation(paths, options)
          caller_reference = "middleman-s3_sync-#{Time.now.to_i}-#{SecureRandom.hex(4)}"
          
          response = cloudfront_client(options).create_invalidation({
            distribution_id: options.cloudfront_distribution_id,
            invalidation_batch: {
              paths: {
                quantity: paths.length,
                items: paths
              },
              caller_reference: caller_reference
            }
          })

          response.invalidation.id
        end

        def cloudfront_client(options)
          @cloudfront_client ||= begin
            client_options = {
              region: 'us-east-1' # CloudFront is always in us-east-1
            }

            # Use the same credentials as S3 if available
            if options.aws_access_key_id && options.aws_secret_access_key
              client_options.merge!({
                access_key_id: options.aws_access_key_id,
                secret_access_key: options.aws_secret_access_key
              })

              # If using an assumed role
              client_options.merge!({
                session_token: options.aws_session_token
              }) if options.aws_session_token
            end

            Aws::CloudFront::Client.new(client_options)
          end
        end

        def reset_cloudfront_client!
          @cloudfront_client = nil
        end

        def wait_for_invalidations(invalidation_ids, options)
          invalidation_ids.each do |invalidation_id|
            say_status "Waiting for invalidation #{invalidation_id}..."
            
            client = cloudfront_client(options)
            client.wait_until(:invalidation_completed, 
              distribution_id: options.cloudfront_distribution_id,
              id: invalidation_id
            ) do |waiter|
              waiter.max_attempts = 30  # Wait up to 30 minutes (30 * 60s checks)
              waiter.delay = 60         # Check every 60 seconds
              
              waiter.before_attempt do |attempt|
                say_status "Checking invalidation status (attempt #{attempt}/30)..." if options.verbose
              end
            end
          end
        rescue Aws::Waiters::Errors::WaiterFailed => e
          say_status "#{ANSI.yellow{'Warning:'}} CloudFront invalidation wait timed out: #{e.message}"
          say_status "Invalidation is still in progress but sync will continue"
        rescue Aws::CloudFront::Errors::ServiceError => e
          say_status "#{ANSI.yellow{'Warning:'}} CloudFront invalidation wait failed: #{e.message}"
          say_status "Invalidation may still be in progress"
        end
      end
    end
  end
end