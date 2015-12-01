# Middleman::S3Sync

[![Join the chat at https://gitter.im/fredjean/middleman-s3_sync](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/fredjean/middleman-s3_sync?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge) [![Code Climate](https://codeclimate.com/github/fredjean/middleman-s3_sync.png)](https://codeclimate.com/github/fredjean/middleman-s3_sync) [![Build Status](https://travis-ci.org/fredjean/middleman-s3_sync.png?branch=master)](https://travis-ci.org/fredjean/middleman-s3_sync)

This gem determines which files need to be added, updated and optionally deleted
and only transfer these files up. This reduces the impact of an update
on a web site hosted on S3.

## Why not Middleman Sync?

[Middleman Sync](https://github.com/karlfreeman/middleman-sync) does a
great job to push [Middleman](http://middlemanapp.com)  generated
websites to S3. The only issue I have with it is that it pushes
every files under build to S3 and doesn't seem to properly delete files
that are no longer needed.

## Installation

Add this line to your application's Gemfile:

    gem 'middleman-s3_sync'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install middleman-s3_sync

## Usage

You need to add the following code to your ```config.rb``` file:

```ruby
activate :s3_sync do |s3_sync|
  s3_sync.bucket                     = 'my.bucket.com' # The name of the S3 bucket you are targetting. This is globally unique.
  s3_sync.region                     = 'us-west-1'     # The AWS region for your bucket.
  s3_sync.aws_access_key_id          = 'AWS KEY ID'
  s3_sync.aws_secret_access_key      = 'AWS SECRET KEY'
  s3_sync.delete                     = false # We delete stray files by default.
  s3_sync.after_build                = false # We do not chain after the build step by default.
  s3_sync.prefer_gzip                = true
  s3_sync.path_style                 = true
  s3_sync.reduced_redundancy_storage = false
  s3_sync.acl                        = 'public-read'
  s3_sync.encryption                 = false
  s3_sync.prefix                     = ''
  s3_sync.version_bucket             = false
  s3_sync.index_document             = 'index.html'
  s3_sync.error_document             = '404.html'
end
```

You can then start synchronizing files with S3 through ```middleman s3_sync```.

### Configuration Defaults

The following defaults apply to the configuration items:

| Setting                    | Default                            |
| -----------------          | ----------------------------       |
| aws_access_key_id          | ```ENV['AWS_ACCESS_KEY_ID']```     |
| aws_secret_access_key      | ```ENV['AWS_SECRET_ACCESS_KEY']``` |
| bucket                     | ```ENV['AWS_BUCKET']```            |
| delete                     | ```true```                         |
| after_build                | ```false```                        |
| prefer_gzip                | ```true```                         |
| reduced_redundancy_storage | ```false```                        |
| path_style                 | ```true```                         |
| encryption                 | ```false```                        |
| acl                        | ```'public-read'```                |
| version_bucket             | ```false```                        |

You do not need to specify the settings that match the defaults. This
simplify the configuration of the extension:

```ruby
activate :s3_sync do |s3_sync|
  s3_sync.bucket = 'my.bucket.com'
end
```

### Providing AWS Credentials

There are a few ways to provide the AWS credentials for s3_sync:

#### Through ```config.rb```

You can set the aws_access_key_id and aws_secret_access_key in the block
that is passed to the activate method.

> I strongly discourage using this method. This will lead you to add and commit these changes
> to your SCM and potentially expose sensitive information to the world.

#### Through ```.s3_sync``` File

You can create a ```.s3_sync``` at the root of your middleman project.
The credentials are passed in the YAML format. The keys match the
options keys.

The .s3_sync file takes precedence to the configuration passed in the
activate method.

A sample ```.s3_sync``` file is included at the root of this repo.

> Make sure to add .s3_sync to your ignore list if you choose this approach. Not doing so may expose
> credentials to the world.

#### Through Environment

You can also pass the credentials through environment variables. They
map to the following values:

| Setting               | Environment Variable               |
| --------------------- | ---------------------------------- |
| aws_access_key_id     | ```ENV['AWS_ACCESS_KEY_ID']```     |
| aws_secret_access_key | ```ENV['AWS_SECRET_ACCESS_KEY']``` |
| bucket                | ```ENV['AWS_BUCKET']```            |

The environment is used when the credentials are not set in the activate
method or passed through the ```.s3_sync``` configuration file.

#### Through IAM role

Alternatively, if you are running builds on EC2 instance which has approrpiate IAM role, then you don't need to think about specifying credentials at all – they will be pulled from AWS metadata server.

### IAM Policy

Here's a sample IAM policy that will allow a user to update the site
contained in a bucket named "mysite.com":

```
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": "arn:aws:s3:::mysite.com"
    },
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": "arn:aws:s3:::mysite.com/*"
    }
  ]
}
```

This will give full access to both the bucket and it's contents.

## Push All Content to S3

There are situations where you might need to push the files to S3. In
such case, you can pass the ```--force``` option:

    $ middleman s3_sync --force

## Overriding the destination bucket

You can override the destination bucket using the --bucket switch.
The command is:

    $ middleman s3_sync --bucket=my.new.bucket

## Overriding the destination prefix

You can override the destination prefix using the `--prefix` switch. The
command is:

    $ middleman s3_sync --prefix=my/new/prefix

## Pushing to a folder within a bucket

You can push to a folder within an S3 bucket by adding using the prefix
option in the config block:

```ruby
activate :s3_sync do |s3_sync|
  # ...
  s3_sync.prefix = 'prefix'
end
```

## Bucket Versioning

You can enable bucket versioning by setting the ```version_bucket```
setting to true within the bucket configuration.

Versioning is enabled at the bucket level, not at the object level.

You can [find out more about versioning here](https://aws.amazon.com/about-aws/whats-new/2010/02/08/versioning-feature-for-amazon-s3-now-available/).

## HTTP Caching

By default, ```middleman-s3_sync``` does not set caching headers. In
general, the default settings are sufficient. However, there are
situations where you might want to set a different HTTP caching policy.
This may be very helpful if you are using the ```asset_hash```
extension.

### Setting a policy based on the mime-type of a file

You can set a caching policy for every files that match a certain
mime-type. For example, setting max-age to 0 and kindly asking the
browser to revalidate the content for HTML files would take the
following form:

```ruby
caching_policy 'text/html', max_age: 0, must_revalidate: true
```

As a result, the following ```Cache-Control``` header would be set to ```max-age:0, must-revalidate```

### Setting a Default Policy

You can set the default policy by passing an options hash to ```default_caching_policy``` in your ```config.rb``` file after the ```activate :s3_sync ... end``` block:

```ruby
default_caching_policy max_age:(60 * 60 * 24 * 365)
```

This will apply the policy to any file that do not have a mime-type
specific policy.

### Caching Policies

The [Caching Tutorial](http://www.mnot.net/cache_docs/) is a great
introduction to HTTP caching. The caching policy code in this gem is
based on it.

The following keys can be set:

| Key                | Value   | Header             | Description                                                                                                                            |
| ---                | ----    | ------             | -----------                                                                                                                            |
| `max_age`          | seconds | `max-age`          | Specifies the maximum amount of time that a representation will be considered fresh. This value is relative to the time of the request |
| `s_maxage`         | seconds | `s-maxage`         | Only applies to shared (proxies) caches                                                                                                |
| `public`           | boolean | `public`           | Marks authenticated responses as cacheable.                                                                                            |
| `private`          | boolean | `private`          | Allows caches that are specific to one user to store the response. Shared caches (proxies) may not.                                    |
| `no_cache`         | boolean | `no-cache`         | Forces caches to submit the request to the origin server for validation before releasing a cached copy, every time.                    |
| `no_store`         | boolean | `no-store`         | Instructs caches not to keep a copy of the representation under any conditions.                                                        |
| `must_revalidate`  | boolean | `must-revalidate`  | Tells the caches that they must obey any freshness information you give them about a representation.                                   |
| `proxy_revalidate` | boolean | `proxy-revalidate` | Similar as `must-revalidate`, but only for proxies.                                                                                    |

### Setting `Expires` Header

You can pass the `expires` key to the `caching_policy` and
`default_caching_policy` methods if you insist on setting the expires
header on a results. You will need to pass it a Time object indicating
when the resourse is set to expire.

> Note that the `Cache-Control` header will take precedence over the
> `Expires` header if both are present.

### A Note About Browser Caching

Browser caching is well specified. It hasn't always been the case.
Still, even modern browsers have different behaviors if it suits it's
developers or their employers. Specs are meant to be ignored and so they
are (I'm looking at you Chrome!). Setting the `Cache-Control` or
`Expires` headers are not a guarrantie that the browsers and the proxies
that stand between them and your content will behave the way you want
them to. YMMV.

### Path Specific Content Type

You can now set the content type of a path through the
```s3_sync.content_types``` hash. This hasi will take precendence over
the content type discovered by the mime_types gem. The [associated pull
request](https://github.com/fredjean/middleman-s3_sync/pull/87) has a
few good examples on how to use this feature.

### ACLs

```middleman-s3_sync``` will set the resources's ACL to ```public-read``` by default. You
can specificy a different ACL via the ```acl``` configuration option.
The valid values are:

* ```private```
* ```public-read```
* ```public-read-write```
* ```authenticated-read```
* ```bucket-owner-read```
* ```bucket-owner-full-control```

The full values and their semantics are [documented on AWS's
documentation
site](http://docs.aws.amazon.com/AmazonS3/latest/dev/ACLOverview.html#CannedACL).

### Encryption

You can ask Amazon to encrypt your files at rest by setting the
```encryption``` option to true. [Server side encryption is documented
on the AWS documentation
site](http://docs.aws.amazon.com/AmazonS3/latest/dev/UsingServerSideEncryption.html)
.

### GZipped Content Encoding

You can set the ```prefer_gzip``` option to look for a gzipped version
of a resource. The gzipped version of the resource will be pushed to S3
instead of the original and the ```Content-Encoding``` and ```Content-Type```
headers will be set correctly. This will cause Amazon to serve the
compressed version of the resource. In order for this to work, you need to
have the `:gzip` extension activated in your `config.rb`.

#### Custom S3 Index and Error Documents

You can enable a custom [index document](http://docs.aws.amazon.com/AmazonS3/latest/dev/IndexDocumentSupport.html)
and [error document](http://docs.aws.amazon.com/AmazonS3/latest/dev/CustomErrorDocSupport.html)
settings. The ```index_document``` option tells which file name gets used as
the index document of a directory (typically, ```index.html```), while
```error_document``` specifies the document to display for 4xx errors (ie,
the 404 page).

## A Debt of Gratitude

I used Middleman Sync as a template for building a Middleman extension.
The code is well structured and easy to understand and it was easy to
extend it to add my synchronization code. My gratitude goes to @karlfreeman
and his work on Middleman sync.

Many thanks to [Gnip](http://gnip.com) and [dojo4](http://dojo4.com) for
supporting and sponsoring work on middleman-s3_sync.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
