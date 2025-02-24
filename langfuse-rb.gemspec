require_relative 'lib/langfuse/version'

Gem::Specification.new do |spec|
  spec.name          = "langfuse-rb"
  spec.version       = Langfuse::VERSION
  spec.authors       = ["Langfuse"]
  spec.email         = ["info@langfuse.com"]

  spec.summary       = "Ruby client for Langfuse - the open source LLM engineering platform"
  spec.description   = "Langfuse Ruby client provides observability and tracing for LLM applications"
  spec.homepage      = "https://github.com/langfuse/langfuse-rb"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.6.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/langfuse/langfuse-rb"
  spec.metadata["changelog_uri"] = "https://github.com/langfuse/langfuse-rb/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob(%w[lib/**/*.rb README.md LICENSE])
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "ruby-openai", "~> 7.0"

  # Explicitly specify the main entry point file
  spec.bindir = "bin"
  spec.executables = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
end