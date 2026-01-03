# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

middleman-s3_sync is a Ruby gem that provides intelligent S3 synchronization for Middleman static sites. Unlike other sync tools, it only transfers files that have been added, updated, or deleted, making deployments more efficient. The gem also supports CloudFront cache invalidation and advanced caching policies.

## Key Commands

### Development
```bash
# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/resource_spec.rb

# Run tests with verbose output
bundle exec rspec -fd

# Build the gem
bundle exec rake build

# Install the gem locally for testing
bundle exec rake install
```

### Testing & Quality
```bash
# Run all specs
bundle exec rake spec  # or just `rake` (default task)

# Run specific test patterns
bundle exec rspec spec/*_spec.rb --pattern "*policy*"

# Check gem build without installing
gem build middleman-s3_sync.gemspec
```

## Architecture

### Core Components

**Main Sync Engine** (`lib/middleman/s3_sync.rb`)
- Central orchestration of sync operations
- Thread-safe S3 operations using mutexes
- Parallel processing (8 threads by default) for file operations
- Tracks CloudFront invalidation paths during sync

**Extension Integration** (`lib/middleman-s3_sync/extension.rb`)
- Middleman extension that hooks into the build process
- Configurable options with environment variable fallbacks
- Resource list manipulation to prepare files for sync

**CLI Commands** (`lib/middleman-s3_sync/commands.rb`)
- Thor-based command-line interface
- Extensive option parsing for CloudFront, AWS credentials, and sync behavior
- Support for dry-run mode and build-then-sync workflows

**Resource Management** (`lib/middleman/s3_sync/resource.rb`)
- Individual file resource handling and status determination
- MD5-based change detection and caching policy application

**CloudFront Integration** (`lib/middleman/s3_sync/cloudfront.rb`)
- Intelligent cache invalidation with batch processing
- Rate limit handling and retry logic
- Path optimization and wildcard support

### Key Design Patterns

- **Thread Safety**: Uses mutexes for bucket and bucket_files operations
- **Parallel Processing**: Leverages `parallel` gem for concurrent S3 operations
- **Status-Based Operations**: Resources maintain state (create, update, delete, ignore)
- **Configuration Cascade**: CLI options override config.rb options override .s3_sync file options override environment variables

### File Status Logic

The gem determines what to do with each file by comparing:
- Local file MD5 hashes vs S3 ETags
- Presence in local build vs S3 bucket
- Caching policies and content encoding preferences

## Testing Strategy

**RSpec Structure**:
- `caching_policy_spec.rb`: HTTP caching header generation
- `cloudfront_spec.rb`: CloudFront invalidation logic (comprehensive, 18k lines)
- `resource_spec.rb`: Individual file resource operations
- `s3_sync_integration_spec.rb`: End-to-end sync workflows

**Mock Strategy**: Uses AWS SDK stub responses and custom S3 object mocks for isolated testing without real AWS calls.

## Configuration Files

- **`.s3_sync`**: YAML configuration file for credentials and options (should be gitignored)
- **`config.rb`**: Middleman configuration with `activate :s3_sync` block
- **Environment Variables**: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_BUCKET, etc.

## Development Rules

**All changes must be accompanied with unit tests.** This is non-negotiable for maintaining code quality and preventing regressions.

## Common Development Patterns

When adding new functionality:
1. Add option to `extension.rb` with appropriate defaults
2. Add CLI flag to `commands.rb` if user-facing
3. Implement core logic in main `s3_sync.rb` module
4. Add comprehensive specs following existing patterns
5. Update README.md with new configuration options

The codebase emphasizes security (credential handling), efficiency (parallel operations), and reliability (comprehensive error handling and dry-run support).
