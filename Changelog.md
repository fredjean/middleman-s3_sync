# Middleman::S3Sync Changelog

The gem that tries really hard not to push files to S3.

## v4.8.0
- Add `immutable` directive to caching policies. Pair with a long `max_age` on
  fingerprinted assets (e.g. those produced by Middleman's `asset_hash`
  extension) to tell browsers they never need to revalidate:
  `caching_policy 'text/css', max_age: 1.year, public: true, immutable: true`.
- Prefer `Cache-Control: max-age` over the `Expires` header. When a policy sets
  `max_age:`, the `Expires` header is now suppressed even if `expires:` is also
  set. Per RFC 7234 §5.3, `max-age` overrides `Expires` for HTTP/1.1 caches, so
  emitting both adds no information and forces a metadata update on every build
  as the `expires:` timestamp drifts forward. Existing configs that rely solely
  on `expires:` (without `max_age:`) continue to work unchanged.
- Resource uploads no longer include empty `cache_control` or `expires` keys
  when the caching policy yields `nil` for them.
- Drop `timerizer` development dependency. Its monkey-patch of `Time.new` was
  incompatible with Ruby 3.1.7's keyword-argument changes and crashed RSpec at
  startup on the 3.1 CI matrix. The three test usages were replaced with plain
  `Time` literals.

## v4.7.0
- Add `after_s3_sync` callback hook that runs after sync completes (#138).
  Accepts a lambda/proc — optionally receiving a results hash with `created`,
  `updated`, `deleted` counts and invalidation paths — or a symbol referencing
  a method on the Middleman app. Zero-arg callbacks work without modification
  via arity detection. Callback failures are logged but do not abort the sync.
- Add `scan_build_dir` option (default: `false`) to sync files in the build
  directory that aren't in the Middleman sitemap (#108, #137). Useful for
  output from `after_build` callbacks, image optimizers, or anything placed
  in `build/` outside the sitemap.
- Add `routing_rules` option to configure S3 website routing rules at sync
  time, so deployments don't overwrite manually-configured rules (#142).
  Supports `condition.key_prefix_equals`,
  `condition.http_error_code_returned_equals`, and the
  `redirect.{host_name, http_redirect_code, protocol, replace_key_prefix_with,
  replace_key_with}` keys. Requires `index_document` to also be set.
- Improve content type detection with a `mime-types` fallback for files
  Middleman doesn't classify (e.g. orphan files, WebP, woff2). The
  `content_types` option is now checked first, and unknown extensions default
  to `application/octet-stream`. Bumped `mime-types` constraint to `~> 3.4`.
  (#161)
- Fix sitemap population for build-mode extensions (#116, #128). The sync
  now calls `ensure_resource_list_updated!` so extensions like blog and
  asset_hash populate the sitemap, and always runs in `:build` mode so
  `configure :build` blocks are active. Files emitted by `after_build`
  callbacks still aren't visible to the sitemap — use `scan_build_dir` for
  those.
- Fix `Resource#redirect?` to return `true`/`false` instead of a truthy URL
  string (#143). The status logic was already correct; this just normalizes
  the boolean contract.
- Tighten gemspec dependency bounds and require Ruby `>= 3.0` (#167).
  Pessimistic constraints on all runtime and development deps to resolve the
  open-ended-dependency warnings on `gem build`.
- Add GitHub Actions CI matrix (Ruby 3.1, 3.2, 3.3, 3.4) and an automated
  RubyGems release workflow that publishes on `v*` tags (#169).

## v4.6.5
- Performance and stability improvements
  - Thread-safe invalidation path tracking (use Set + mutex) when running in parallel
  - Cache CloudFront client (with reset hook for tests)
  - Single-pass resource categorization (reduce multiple iterations over resources)
  - Batch S3 deletes via delete_objects (up to 1000 keys/request)
  - Stream file uploads to reduce memory; compute MD5s in a single read when possible
  - Optimize CloudFront path deduplication to O(n × path_depth)
  - CLI/extension: support option writers (e.g., verbose=, dry_run=) to fix NoMethodError
- Tests: add coverage for CloudFront, batch delete, and streaming uploads
- No breaking changes; default behavior preserved

## v4.6.4
* Remove map gem dependency and replace with native Ruby implementation
* Add IndifferentHash class to provide string/symbol indifferent access without external dependencies
* Improve gem stability by eliminating dependency on unmaintained library

## v4.6.3
* Restrict incompatible map 8.x installation

## v4.6.2

* Fix AWS SDK parameter format issues from Fog migration
* Fix website configuration parameters to use symbol keys instead of strings
* Fix S3 object metadata parameter format to use correct key suffixes
* Remove obsolete Fog-style constants (CONTENT_MD5_KEY, REDIRECT_KEY)
* Add comprehensive test suite for AWS SDK parameter validation (18 new tests)
* Improve compatibility with AWS SDK v3 to prevent API errors

## v4.6.1

* Add CloudFront rate limit handling with exponential backoff retry logic
* Add configurable retry settings: `cloudfront_invalidation_max_retries` and `cloudfront_invalidation_batch_delay`
* Improve CloudFront error handling for "Rate exceeded" and "Throttling" errors
* Add command line options for retry configuration
* Update documentation with retry configuration examples
* Increase default batch delay from 1 to 2 seconds for better rate limit prevention

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


