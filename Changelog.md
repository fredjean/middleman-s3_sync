# Middleman::S3Sync Changelog

The gem that tries really hard not to push files to S3.

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


