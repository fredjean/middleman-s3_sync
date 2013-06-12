require 'middleman-core'
require 'middleman/s3_sync'

::Middleman::Extensions.register(:s3_sync, '>= 3.0.0') do
  ::Middleman::S3Sync
end

