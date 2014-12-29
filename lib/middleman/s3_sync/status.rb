require 'ansi/code'
require 'ansi/string'

module Middleman
  module S3Sync
    module Status
      def say_status(status)
        puts :s3_sync.to_s.rjust(12).green + "  #{status}"
      end
    end
  end
end
