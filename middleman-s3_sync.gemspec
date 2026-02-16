# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'middleman/s3_sync/version'

Gem::Specification.new do |gem|
  gem.name          = "middleman-s3_sync"
  gem.version       = Middleman::S3Sync::VERSION
  gem.authors       = ["Frederic Jean", "Will Koehler"]
  gem.email         = ["fred@fredjean.net"]
  gem.description   = %q{Only syncs files that have been updated to S3.}
  gem.summary       = %q{Tries really, really hard not to push files to S3.}
  gem.homepage      = "http://github.com/fredjean/middleman-s3_sync"
  gem.license       = 'MIT'

  gem.required_ruby_version = '>= 3.0'

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  # Runtime dependencies
  gem.add_runtime_dependency 'middleman-core', '~> 4.4'
  gem.add_runtime_dependency 'middleman-cli', '~> 4.4'
  gem.add_runtime_dependency 'aws-sdk-s3', '~> 1.187', '>= 1.187.0'
  gem.add_runtime_dependency 'aws-sdk-cloudfront', '~> 1.0'
  gem.add_runtime_dependency 'parallel', '~> 1.20'
  gem.add_runtime_dependency 'ruby-progressbar', '~> 1.11'
  gem.add_runtime_dependency 'ansi', '~> 1.5'
  gem.add_runtime_dependency 'mime-types', '~> 3.4'
  gem.add_runtime_dependency 'nokogiri', '~> 1.18', '>= 1.18.4'

  # Development dependencies
  gem.add_development_dependency 'rake', '~> 13.0'
  gem.add_development_dependency 'pry', '~> 0.14'
  gem.add_development_dependency 'pry-byebug', '~> 3.10'
  gem.add_development_dependency 'rspec', '~> 3.12'
  gem.add_development_dependency 'rspec-support', '~> 3.12'
  gem.add_development_dependency 'rspec-its', '~> 2.0'
  gem.add_development_dependency 'rspec-mocks', '~> 3.12'
  gem.add_development_dependency 'timerizer', '~> 0.3'
  gem.add_development_dependency 'webrick', '~> 1.8'
end
