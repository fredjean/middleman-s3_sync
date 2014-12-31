require 'ansi/code'

module Middleman
  module S3Sync
    module Status
      def say_status(status)
        puts ANSI.green{:s3_sync.to_s.rjust(12)} + "  #{status}"
      end
    end
  end
end
