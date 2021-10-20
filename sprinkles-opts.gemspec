# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'sprinkles/opts/version'

Gem::Specification.new do |spec|
  spec.name          = 'sprinkles-opts'
  spec.version       = Sprinkles::Opts::VERSION
  spec.authors       = ['Getty Ritter']
  spec.email         = ['sprinkles@infinitenegativeutility.com']

  spec.summary       = 'Sorbet-compatible option parser'
  spec.description   = 'A Sorbet-driven library for parsing command-line options'
  spec.homepage      = 'https://github.com/aisamanra/sprinkles-opts'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 2.5', '< 3'
  spec.metadata = {
    'source_code_uri' => 'https://github.com/aisamanra/sprinkles-opts',
  }

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end

  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.17'
  spec.add_development_dependency 'minitest', '~> 5.0'
  spec.add_development_dependency 'rake', '~> 10.0'

  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'sorbet'
  spec.add_dependency 'sorbet-runtime'
end
