require 'faraday'
require 'json'
require 'securerandom'
require 'logger'

module Langfuse
  class Core
    attr_reader :options, :queue, :client

    # Initialize a new Langfuse client
    # @param public_key [String] Langfuse public key
    # @param secret_key [String] Langfuse secret key
    # @param host [String] Langfuse host URL
    # @param options [Hash] Additional options
    def initialize(public_key:, secret_key:, host:, **options)
      @public_key = public_key
      @secret_key = secret_key
      @host = host.chomp('/')
      
      @options = {
        flush_at: options[:flush_at] || 10,
        flush_interval: options[:flush_interval] || 60,
        retry_count: options[:retry_count] || 3,
        retry_delay: options[:retry_delay] || 1,
        enabled: options.fetch(:enabled, true),
        sample_rate: options.fetch(:sample_rate, 1.0),
        additional_headers: options[:additional_headers] || {},
        logger: options[:logger] || Logger.new($stdout)
      }

      @queue = []
      @mutex = Mutex.new
      @timer = nil

      @client = Faraday.new(url: @host) do |conn|
        conn.request :authorization, :basic, @public_key, @secret_key
        conn.request :json
        conn.response :json
        conn.adapter Faraday.default_adapter
      end

      # Start the flush timer
      start_flush_timer
    end

    # Create a new trace
    # @param name [String] Name of the trace
    # @param id [String] Optional ID for the trace, will generate UUID if not provided
    # @param user_id [String] Optional user ID
    # @param session_id [String] Optional session ID
    # @param metadata [Hash] Optional metadata
    # @param tags [Array] Optional tags
    # @return [Trace] A new trace object
    def trace(name:, id: nil, user_id: nil, session_id: nil, metadata: nil, tags: nil)
      Trace.new(self, {
        id: id || SecureRandom.uuid,
        name: name,
        user_id: user_id,
        session_id: session_id,
        metadata: metadata,
        tags: tags,
        timestamp: Time.now
      })
    end

    # Add an event to the queue
    # @param type [String] Type of event (e.g., 'trace', 'generation', 'span')
    # @param body [Hash] Event data
    # @return [Boolean] Whether the event was queued
    def enqueue(type, body)
      return false unless @options[:enabled]
      
      # Apply sampling
      return false if @options[:sample_rate] < 1.0 && rand > @options[:sample_rate]
      
      event = {
        type: type,
        body: body,
        timestamp: Time.now.utc.iso8601
      }
      
      @mutex.synchronize do
        @queue << event
        flush if @queue.size >= @options[:flush_at]
      end
      
      true
    end

    # Flush the queue to the Langfuse API
    # @return [Boolean] Whether the flush was successful
    def flush
      return true if @queue.empty?
      
      events = nil
      @mutex.synchronize do
        events = @queue.dup
        @queue.clear
      end
      
      return true if events.empty?
      
      begin
        response = @client.post('/api/public/ingestion') do |req|
          req.headers.merge!(@options[:additional_headers])
          req.body = { batch: events }
          req.options.timeout = 10
        end
        
        if response.success?
          @options[:logger].debug("Langfuse: Successfully sent #{events.size} events")
          return true
        else
          @options[:logger].error("Langfuse: Failed to send events: #{response.status} - #{response.body}")
          # Re-queue the events if the error is retryable
          requeue_events(events) if retryable_status?(response.status)
          return false
        end
      rescue => e
        @options[:logger].error("Langfuse: Error sending events: #{e.message}")
        # Re-queue the events for network errors
        requeue_events(events)
        return false
      end
    end
    
    # Flush the queue and wait for it to complete
    # @return [Boolean] Whether the flush was successful
    def flush_async
      flush
    end
    
    # Flush and shutdown the client
    # @return [Boolean] Whether the shutdown was successful
    def shutdown
      stop_flush_timer
      flush
    end
    
    private
    
    # Start the flush timer
    def start_flush_timer
      @timer = Thread.new do
        loop do
          sleep(@options[:flush_interval])
          flush
        end
      end
    end
    
    # Stop the flush timer
    def stop_flush_timer
      @timer&.kill
      @timer = nil
    end
    
    # Determine if a status code is retryable
    # @param status [Integer] HTTP status code
    # @return [Boolean] Whether the status is retryable
    def retryable_status?(status)
      status >= 500 || status == 429
    end
    
    # Re-queue events after a failed request
    # @param events [Array] Events to re-queue
    def requeue_events(events)
      @mutex.synchronize do
        @queue.unshift(*events)
      end
    end
  end
  
  # Represents a trace in Langfuse
  class Trace
    attr_reader :id, :name, :client, :data
    
    # Initialize a new trace
    # @param client [Langfuse::Core] Langfuse client
    # @param data [Hash] Trace data
    def initialize(client, data)
      @client = client
      @data = data
      @id = data[:id]
      @name = data[:name]
      
      # Queue the trace creation
      @client.enqueue('trace', @data)
    end
    
    # Add a generation to this trace
    # @param model [String] Model name
    # @param input [Hash|String] Input data
    # @param output [String|Hash] Output data
    # @param name [String] Optional name for the generation
    # @param start_time [Time] Optional start time
    # @param end_time [Time] Optional end time
    # @param usage [Hash] Optional usage statistics
    # @param metadata [Hash] Optional metadata
    # @return [Generation] The created generation
    def generation(model:, input:, output: nil, name: nil, start_time: nil, end_time: nil, usage: nil, metadata: nil)
      id = SecureRandom.uuid
      
      gen_data = {
        id: id,
        trace_id: @id,
        name: name,
        model: model,
        input: input,
        output: output,
        start_time: start_time || Time.now,
        end_time: end_time,
        usage: usage,
        metadata: metadata
      }.compact
      
      @client.enqueue('generation', gen_data)
      
      Generation.new(@client, gen_data)
    end
    
    # Add a span to this trace
    # @param name [String] Name of the span
    # @param start_time [Time] Optional start time
    # @param end_time [Time] Optional end time
    # @param metadata [Hash] Optional metadata
    # @return [Span] The created span
    def span(name:, start_time: nil, end_time: nil, metadata: nil)
      id = SecureRandom.uuid
      
      span_data = {
        id: id,
        trace_id: @id,
        name: name,
        start_time: start_time || Time.now,
        end_time: end_time,
        metadata: metadata
      }.compact
      
      @client.enqueue('span', span_data)
      
      Span.new(@client, span_data)
    end
    
    # Update this trace
    # @param user_id [String] Optional user ID
    # @param session_id [String] Optional session ID
    # @param metadata [Hash] Optional metadata
    # @param tags [Array] Optional tags
    # @return [Trace] Self
    def update(user_id: nil, session_id: nil, metadata: nil, tags: nil)
      update_data = {
        id: @id,
        user_id: user_id,
        session_id: session_id,
        metadata: metadata,
        tags: tags
      }.compact
      
      return self if update_data.keys.size <= 1 # Only id is present
      
      @client.enqueue('update-trace', update_data)
      @data.merge!(update_data)
      
      self
    end
  end
  
  # Represents a generation in Langfuse
  class Generation
    attr_reader :id, :trace_id, :client, :data
    
    # Initialize a new generation
    # @param client [Langfuse::Core] Langfuse client
    # @param data [Hash] Generation data
    def initialize(client, data)
      @client = client
      @data = data
      @id = data[:id]
      @trace_id = data[:trace_id]
    end
    
    # Update this generation
    # @param output [String|Hash] Optional output data
    # @param end_time [Time] Optional end time
    # @param usage [Hash] Optional usage statistics
    # @param metadata [Hash] Optional metadata
    # @return [Generation] Self
    def update(output: nil, end_time: nil, usage: nil, metadata: nil)
      update_data = {
        id: @id,
        output: output,
        end_time: end_time || Time.now,
        usage: usage,
        metadata: metadata
      }.compact
      
      return self if update_data.keys.size <= 1 # Only id is present
      
      @client.enqueue('update-generation', update_data)
      @data.merge!(update_data)
      
      self
    end
  end
  
  # Represents a span in Langfuse
  class Span
    attr_reader :id, :trace_id, :client, :data
    
    # Initialize a new span
    # @param client [Langfuse::Core] Langfuse client
    # @param data [Hash] Span data
    def initialize(client, data)
      @client = client
      @data = data
      @id = data[:id]
      @trace_id = data[:trace_id]
    end
    
    # Update this span
    # @param end_time [Time] Optional end time
    # @param metadata [Hash] Optional metadata
    # @return [Span] Self
    def update(end_time: nil, metadata: nil)
      update_data = {
        id: @id,
        end_time: end_time || Time.now,
        metadata: metadata
      }.compact
      
      return self if update_data.keys.size <= 1 # Only id is present
      
      @client.enqueue('update-span', update_data)
      @data.merge!(update_data)
      
      self
    end
  end
end