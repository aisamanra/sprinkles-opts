# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'sprinkles/opts/version'

Gem::Specification.new do |spec|
  spec.name          = 'sprinkles-opts'
  spec.version       = Sprinkles::Opts::VERSION
  spec.authors       = ['Getty Ritter']
  spec.email         = ['tristero@infinitenegativeutility.com']

  spec.summary       = 'something'
  spec.description   = 'something'
  spec.homepage      = 'https://sprinkles-opts.gdritter.com'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 2.5', '< 3'

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = 'https://sprinkles.gdritter.com'

    spec.metadata['homepage_uri'] = spec.homepage
    spec.metadata['source_code_uri'] = 'https://sprinkles.gdritter.com'
    spec.metadata['changelog_uri'] = 'https://sprinkles.gdritter.com'
  else
    raise 'RubyGems 2.0 or newer is required to protect against ' \
      'public gem pushes.'
  end

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.17'
  spec.add_development_dependency 'minitest', '~> 5.0'
  spec.add_development_dependency 'rake', '~> 10.0'

  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'sorbet'
  spec.add_dependency 'sorbet-runtime'
end
