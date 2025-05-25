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

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_runtime_dependency 'middleman-core'
  gem.add_runtime_dependency 'middleman-cli'
  gem.add_runtime_dependency 'unf'
  gem.add_runtime_dependency 'aws-sdk-s3'
  gem.add_runtime_dependency 'aws-sdk-cloudfront'
  gem.add_runtime_dependency 'map'
  gem.add_runtime_dependency 'parallel'
  gem.add_runtime_dependency 'ruby-progressbar'
  gem.add_runtime_dependency 'ansi', '~> 1.5.0'
  gem.add_runtime_dependency 'mime-types', '~> 3.1'
  gem.add_runtime_dependency 'base64'
  gem.add_runtime_dependency 'nokogiri', '>= 1.18.4'

  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'pry'
  gem.add_development_dependency 'pry-byebug'
  gem.add_development_dependency 'rspec'
  gem.add_development_dependency 'rspec-support'
  gem.add_development_dependency 'rspec-its'
  gem.add_development_dependency 'rspec-mocks'
  gem.add_development_dependency 'timerizer'
  gem.add_development_dependency 'webrick'
end
