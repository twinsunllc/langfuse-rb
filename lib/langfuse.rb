# Make sure these are loaded and available
require 'faraday'
require 'json'
require 'securerandom'
require 'logger'
require 'thread'

# Load version first
require_relative 'langfuse/version'

module Langfuse
  class Error < StandardError; end

  # Load all components within the module scope
  require_relative 'langfuse/core'
  require_relative 'langfuse/openai'

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
  # @option options [Boolean] :disable_background_flush Disable background flush timer thread (default: false)
  # @return [Langfuse::Core] A new Langfuse client
  def self.new(public_key:, secret_key:, host: 'https://cloud.langfuse.com', **options)
    Langfuse::Core.new(
      public_key: public_key,
      secret_key: secret_key,
      host: host,
      **options
    )
  end

  # Get a thread-local Langfuse client
  # This is useful for multi-threaded environments like Sidekiq
  # @param public_key [String] Langfuse public key
  # @param secret_key [String] Langfuse secret key
  # @param host [String] Langfuse host URL (default: 'https://cloud.langfuse.com')
  # @param options [Hash] Additional options (see #new for details)
  # @return [Langfuse::Core] A thread-local Langfuse client
  def self.thread_local_client(public_key:, secret_key:, host: 'https://cloud.langfuse.com', **options)
    thread_key = :langfuse_thread_local_client

    # Return existing client if it exists for this thread
    return Thread.current[thread_key] if Thread.current[thread_key]

    # Create a new client with background flush disabled by default for thread-local clients
    options[:disable_background_flush] = true unless options.key?(:disable_background_flush)

    # Create and store the client
    Thread.current[thread_key] = Langfuse::Core.new(
      public_key: public_key,
      secret_key: secret_key,
      host: host,
      **options
    )
  end

  # Clear the thread-local client
  # Call this when you're done with the client to free resources
  def self.clear_thread_local_client
    Thread.current[:langfuse_thread_local_client] = nil
  end
end