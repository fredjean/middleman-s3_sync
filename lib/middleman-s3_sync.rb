require 'middleman-core'
require 'middleman-s3_sync/commands'
require 'middleman/s3_sync'

::Middleman::Extensions.register(:s3_sync) do
  require 'middleman-s3_sync/extension'
  ::Middleman::S3SyncExtension
end
