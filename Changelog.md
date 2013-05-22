# Middleman::S3Sync Changelog

The gem that tries really hard not to push files to S3.

## v3.0.12

* Remove S3 objects that look like directories. Addresses [issue
#13](https://github.com/fredjean/middleman-s3_sync/issues/13)

## v3.0.11

* Adds support for GZipped resources (fixes #3)
* Quiets Fog's warning messages (fixes #10)
* Rename the options method to s3_sync_options to remove a method name collision (fixes #9)
* Colorize the output.


