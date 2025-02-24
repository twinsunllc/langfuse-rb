require_relative 'langfuse/version'
require_relative 'langfuse/core'
require_relative 'langfuse/openai'

# Make sure these are loaded and available
require 'faraday'
require 'json'
require 'securerandom'
require 'logger'
require 'singleton'

module Langfuse
  class Error < StandardError; end
  
  # Create a new Langfuse client instance
  # @param public_key [String] Langfuse public key
  # @param secret_key [String] Langfuse secret key
  # @param host [String] Langfuse host URL (default: 'https://cloud.langfuse.com')
  # @param options [Hash] Additional options
  # @option options [Integer] :flush_at Number of events to collect before sending to server (default: 10)
  # @option options [Integer] :flush_interval Number of seconds to wait before sending to server (default: 60)
  # @option options [Integer] :retry_count Number of retries to attempt (default: 3)
  # @option options [Integer] :retry_delay Delay between retries in seconds (default: 1)
  # @option options [Boolean] :enabled Whether this client is enabled (default: true)
  # @option options [Float] :sample_rate Sampling rate between 0 and 1 (default: 1.0)
  # @return [Langfuse::Core] A new Langfuse client
  def self.new(public_key:, secret_key:, host: 'https://cloud.langfuse.com', **options)
    Langfuse::Core.new(
      public_key: public_key,
      secret_key: secret_key,
      host: host,
      **options
    )
  end
end