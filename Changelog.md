# Middleman::S3Sync Changelog

The gem that tries really hard not to push files to S3.

## v4.6.0

* Add comprehensive CloudFront invalidation support with smart path tracking
* Add CloudFront configuration options and command line switches
* Add batch processing for CloudFront invalidations to respect API limits
* Add path normalization and deduplication for efficient invalidations
* Add dry-run support for CloudFront invalidations
* Add wait functionality for CI/CD pipeline integration
* Update README with CloudFront documentation and best practices

## v4.5.0

* Migrate from Fog gem to native AWS SDK S3 client
* Remove numerous transitive dependencies by dropping Fog
* Fix path handling inconsistencies with leading slashes
* Improve resource handling for AWS SDK v3 compatibility
* Add Ruby 3.2 compatibility fixes
* Fix build behavior to not auto-build unless explicitly requested
* Optimize resource processing for better performance
* Update nokogiri dependency for security
* Enhance test coverage and mocking

## v4.4.0

* Add support for newer Ruby versions (3.0+)
* Update dependencies for security and compatibility
* Fix deprecation warnings with newer Ruby versions
* Improve error handling and logging

## v4.3.0

* Enhanced S3 client configuration options
* Improved AWS credential handling
* Better support for custom S3 endpoints
* Performance optimizations for large sites

## v4.2.0

* Add support for S3 transfer acceleration
* Improve concurrent upload handling
* Enhanced progress reporting
* Better error messages and debugging

## v4.1.0

* Add support for custom content types
* Improve gzip handling and encoding detection
* Enhanced caching policy management
* Better support for redirects and metadata

## v4.0.1

* Fix order of manipulator chain so that S3 Sync is always the last action
* Add --aws_access_key_id / --aws_secret_access_key as command line switches
* Add --build command line switch, which triggers a build before syncing
* Bump dependency version of middleman-core to 4.0.0.rc.1

## v4.0.0

* Initial support for Middleman v4
* Fix errors related to ANSI format on Windows
* Fix null reference errors in resource class
* Add --environment and --instrument command line switches
* Remove duplicate extension registration
* Remove after_s3_sync hook as hooks are no longer supported in Middleman v4

## v3.0.22

* Fixes a bug where files were not closed, leading to an exhaustion of 
  file handles with large web sites.
* Internal fixes.

## v3.0.17

* Limits the number of concurrent threads used while processing the
  resources and files. (#21)
* Adds the option to use reduced redundancy storage for the bucket. (#8)
* Adds the license to the gem specs. (#20)
* Makes sure tha the .s3_sync file is read when the sync occures within
  a build. (#22, #23)

## v3.0.16

* Adds the ignore directory and redirects logic to the --force option as
  well.

## v3.0.15

* Ignore objects that look like directories. In some cases, S3 objects
  where created to simulate directories. S3 Sync would crash when
  processing these and a matching local directory was present.

## v3.0.14

* No longer deletes redirects from the S3 bucket. This prevents a
  situation where the redirect is first removed then added back through
  [middleman-s3_redirect](https://github.com/fredjean/middleman-s3_redirect).

## v3.0.13

* Fails gracefully when the extension isn't activated

## v3.0.12

* Remove S3 objects that look like directories. Addresses [issue
#13](https://github.com/fredjean/middleman-s3_sync/issues/13)

## v3.0.11

* Adds support for GZipped resources (fixes #3)
* Quiets Fog's warning messages (fixes #10)
* Rename the options method to s3_sync_options to remove a method name collision (fixes #9)
* Colorize the output.


