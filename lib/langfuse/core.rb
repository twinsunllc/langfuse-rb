require 'faraday'
require 'json'
require 'securerandom'
require 'logger'
require 'thread'
require 'timeout'

module Langfuse
  # Helper method to format timestamps consistently throughout the library
  def self.format_timestamp(time)
    return Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S.%LZ') if time.nil?

    case time
    when Time
      time.utc.strftime('%Y-%m-%dT%H:%M:%S.%LZ')
    when String
      # Return as-is if it's already a formatted string
      time
    else
      time.to_s
    end
  end

  # Observation types as defined in the API schema
  module ObservationType
    SPAN = "SPAN"
    GENERATION = "GENERATION"
    EVENT = "EVENT"
  end

  # Observation levels as defined in the API schema
  module ObservationLevel
    DEBUG = "DEBUG"
    DEFAULT = "DEFAULT"
    WARNING = "WARNING"
    ERROR = "ERROR"
  end

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
        logger: options[:logger] || Logger.new($stdout),
        disable_background_flush: options.fetch(:disable_background_flush, false)
      }

      # Use a thread-safe Queue
      @queue = Queue.new
      @timer = nil

      @client = Faraday.new(url: @host) do |conn|
        conn.request :authorization, :basic, @public_key, @secret_key
        conn.request :json
        conn.response :json
        conn.adapter Faraday.default_adapter
      end

      # Start the flush timer unless disabled
      start_flush_timer unless @options[:disable_background_flush]
    end

    # Create a new trace
    # @param name [String] Name of the trace
    # @param id [String] Optional ID for the trace, will generate UUID if not provided
    # @param user_id [String] Optional user ID
    # @param session_id [String] Optional session ID
    # @param metadata [Hash] Optional metadata
    # @param tags [Array] Optional tags
    # @param version [String] Optional version
    # @param release [String] Optional release
    # @param public_trace [Boolean] Optional public flag
    # @param input [Hash|String] Optional input data
    # @param output [Hash|String] Optional output data
    # @return [Trace] A new trace object
    def trace(name:, id: nil, user_id: nil, session_id: nil, metadata: nil, tags: nil,
             version: nil, release: nil, public_trace: nil, input: nil, output: nil)
      Trace.new(self, {
        id: id || SecureRandom.uuid,
        name: name,
        userId: user_id,
        sessionId: session_id,
        metadata: metadata,
        tags: tags,
        version: version,
        release: release,
        public: public_trace,
        input: input,
        output: output,
        timestamp: Langfuse.format_timestamp(Time.now)
      })
    end

    # Add an event to the queue
    # @param type [String] Type of event (e.g., 'trace-create', 'generation-create', 'span-create')
    # @param body [Hash] Event data
    # @return [Boolean] Whether the event was queued
    def enqueue(type, body)
      return false unless @options[:enabled]

      # Apply sampling
      return false if @options[:sample_rate] < 1.0 && rand > @options[:sample_rate]

      event = {
        id: SecureRandom.uuid,  # Add required id for the event itself
        type: type,
        body: body,  # Body is now properly nested
        timestamp: Langfuse.format_timestamp(Time.now)
      }

      # Add to the thread-safe queue
      @queue.push(event)

      # Check if we should flush based on queue size
      flush if @queue.size >= @options[:flush_at]

      true
    end

    # Flush the queue to the Langfuse API
    # @return [Boolean] Whether the flush was successful
    def flush
      # Quick check if queue is empty
      return true if @queue.empty?

      # Drain the queue into a local array
      # This is thread-safe because Queue#pop is thread-safe
      events = []
      until @queue.empty?
        begin
          events << @queue.pop(true) # non-blocking pop
        rescue ThreadError
          # Queue is empty
          break
        end
      end

      return true if events.empty?

      begin
        response = @client.post('/api/public/ingestion') do |req|
          req.headers.merge!(@options[:additional_headers])
          req.body = { batch: events }
          req.options.timeout = 10
        end

        @options[:logger].debug("Langfuse: Request body: #{JSON.pretty_generate({ batch: events })}")
        @options[:logger].debug("Langfuse: Response status: #{response.status}")
        @options[:logger].debug("Langfuse: Response body: #{JSON.pretty_generate(response.body)}")

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
          begin
            flush
          rescue => e
            @options[:logger].error("Langfuse: Error during timer flush: #{e.message}")
          end
        end
      end

      # Set thread as daemon so it doesn't prevent program exit
      @timer.abort_on_exception = false
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
      # Add events back to the queue
      # This is thread-safe because Queue#push is thread-safe
      events.each do |event|
        @queue.push(event)
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
      @client.enqueue('trace-create', @data)
    end

    # Add a generation to this trace
    # @param model [String] Model name
    # @param input [Hash|String] Input data
    # @param output [String|Hash] Output data
    # @param name [String] Optional name for the generation
    # @param start_time [Time] Optional start time
    # @param end_time [Time] Optional end time
    # @param completion_start_time [Time] Optional completion start time
    # @param model_parameters [Hash] Optional model parameters
    # @param usage [Hash] Optional usage statistics
    # @param usage_details [Hash] Optional detailed usage statistics
    # @param cost_details [Hash] Optional cost details
    # @param metadata [Hash] Optional metadata
    # @param level [String] Optional observation level
    # @param status_message [String] Optional status message
    # @param prompt_name [String] Optional prompt name
    # @param prompt_version [Integer] Optional prompt version
    # @param version [String] Optional version
    # @return [Generation] The created generation
    def generation(model:, input:, output: nil, name: nil, start_time: nil, end_time: nil,
                  completion_start_time: nil, model_parameters: nil, usage: nil,
                  usage_details: nil, cost_details: nil, metadata: nil, level: nil,
                  status_message: nil, prompt_name: nil, prompt_version: nil, version: nil)
      id = SecureRandom.uuid

      gen_data = {
        id: id,
        traceId: @id,
        name: name,
        type: ObservationType::GENERATION,
        model: model,
        input: input,
        output: output,
        startTime: Langfuse.format_timestamp(start_time),
        endTime: end_time ? Langfuse.format_timestamp(end_time) : nil,
        completionStartTime: completion_start_time ? Langfuse.format_timestamp(completion_start_time) : nil,
        modelParameters: model_parameters,
        usage: usage,
        usageDetails: usage_details,
        costDetails: cost_details,
        metadata: metadata,
        level: level,
        statusMessage: status_message,
        promptName: prompt_name,
        promptVersion: prompt_version,
        version: version
      }.compact

      @client.enqueue('generation-create', gen_data)

      Generation.new(@client, gen_data)
    end

    # Add a span to this trace
    # @param name [String] Name of the span
    # @param start_time [Time] Optional start time
    # @param end_time [Time] Optional end time
    # @param metadata [Hash] Optional metadata
    # @param input [Hash|String] Optional input data
    # @param output [String|Hash] Optional output data
    # @param level [String] Optional observation level
    # @param status_message [String] Optional status message
    # @param version [String] Optional version
    # @return [Span] The created span
    def span(name:, start_time: nil, end_time: nil, metadata: nil, input: nil, output: nil,
            level: nil, status_message: nil, version: nil)
      id = SecureRandom.uuid

      span_data = {
        id: id,
        traceId: @id,
        name: name,
        type: ObservationType::SPAN,
        startTime: Langfuse.format_timestamp(start_time),
        endTime: end_time ? Langfuse.format_timestamp(end_time) : nil,
        metadata: metadata,
        input: input,
        output: output,
        level: level,
        statusMessage: status_message,
        version: version
      }.compact

      @client.enqueue('span-create', span_data)

      Span.new(@client, span_data)
    end

    # Add an event to this trace
    # @param name [String] Name of the event
    # @param start_time [Time] Optional start time
    # @param metadata [Hash] Optional metadata
    # @param input [Hash|String] Optional input data
    # @param output [String|Hash] Optional output data
    # @param level [String] Optional observation level
    # @param status_message [String] Optional status message
    # @param version [String] Optional version
    # @return [Event] The created event
    def event(name:, start_time: nil, metadata: nil, input: nil, output: nil,
             level: nil, status_message: nil, version: nil)
      id = SecureRandom.uuid

      event_data = {
        id: id,
        traceId: @id,
        name: name,
        type: ObservationType::EVENT,
        startTime: Langfuse.format_timestamp(start_time),
        metadata: metadata,
        input: input,
        output: output,
        level: level,
        statusMessage: status_message,
        version: version
      }.compact

      @client.enqueue('observation-create', event_data)

      Event.new(@client, event_data)
    end

    # Update this trace
    # @param user_id [String] Optional user ID
    # @param session_id [String] Optional session ID
    # @param metadata [Hash] Optional metadata
    # @param tags [Array] Optional tags
    # @param version [String] Optional version
    # @param release [String] Optional release
    # @param public_trace [Boolean] Optional public flag
    # @param input [Hash|String] Optional input data
    # @param output [Hash|String] Optional output data
    # @return [Trace] Self
    def update(user_id: nil, session_id: nil, metadata: nil, tags: nil,
              version: nil, release: nil, public_trace: nil, input: nil, output: nil)
      update_data = {
        id: @id,
        userId: user_id,
        sessionId: session_id,
        metadata: metadata,
        tags: tags,
        version: version,
        release: release,
        public: public_trace,
        input: input,
        output: output
      }.compact

      return self if update_data.keys.size <= 1 # Only id is present

      @client.enqueue('trace-create', update_data)
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
      @trace_id = data[:traceId]
    end

    # Update this generation
    # @param output [String|Hash] Optional output data
    # @param end_time [Time] Optional end time
    # @param completion_start_time [Time] Optional completion start time
    # @param model [String] Optional model name
    # @param model_parameters [Hash] Optional model parameters
    # @param usage [Hash] Optional usage statistics
    # @param usage_details [Hash] Optional detailed usage statistics
    # @param cost_details [Hash] Optional cost details
    # @param metadata [Hash] Optional metadata
    # @param level [String] Optional observation level
    # @param status_message [String] Optional status message
    # @param prompt_name [String] Optional prompt name
    # @param prompt_version [Integer] Optional prompt version
    # @return [Generation] Self
    def update(output: nil, end_time: nil, completion_start_time: nil, model: nil,
              model_parameters: nil, usage: nil, usage_details: nil, cost_details: nil,
              metadata: nil, level: nil, status_message: nil, prompt_name: nil, prompt_version: nil)
      update_data = {
        id: @id,
        output: output,
        endTime: end_time ? Langfuse.format_timestamp(end_time) : nil,
        completionStartTime: completion_start_time ? Langfuse.format_timestamp(completion_start_time) : nil,
        model: model,
        modelParameters: model_parameters,
        usage: usage,
        usageDetails: usage_details,
        costDetails: cost_details,
        metadata: metadata,
        level: level,
        statusMessage: status_message,
        promptName: prompt_name,
        promptVersion: prompt_version
      }.compact

      return self if update_data.keys.size <= 1 # Only id is present

      @client.enqueue('generation-update', update_data)
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
      @trace_id = data[:traceId]
    end

    # Update this span
    # @param end_time [Time] Optional end time
    # @param metadata [Hash] Optional metadata
    # @param input [Hash|String] Optional input data
    # @param output [String|Hash] Optional output data
    # @param level [String] Optional observation level
    # @param status_message [String] Optional status message
    # @return [Span] Self
    def update(end_time: nil, metadata: nil, input: nil, output: nil, level: nil, status_message: nil)
      update_data = {
        id: @id,
        endTime: end_time ? Langfuse.format_timestamp(end_time) : nil,
        metadata: metadata,
        input: input,
        output: output,
        level: level,
        statusMessage: status_message
      }.compact

      return self if update_data.keys.size <= 1 # Only id is present

      @client.enqueue('span-update', update_data)
      @data.merge!(update_data)

      self
    end
  end

  # Represents an event in Langfuse
  class Event
    attr_reader :id, :trace_id, :client, :data

    # Initialize a new event
    # @param client [Langfuse::Core] Langfuse client
    # @param data [Hash] Event data
    def initialize(client, data)
      @client = client
      @data = data
      @id = data[:id]
      @trace_id = data[:traceId]
    end

    # Update this event
    # @param metadata [Hash] Optional metadata
    # @param input [Hash|String] Optional input data
    # @param output [String|Hash] Optional output data
    # @param level [String] Optional observation level
    # @param status_message [String] Optional status message
    # @return [Event] Self
    def update(metadata: nil, input: nil, output: nil, level: nil, status_message: nil)
      update_data = {
        id: @id,
        metadata: metadata,
        input: input,
        output: output,
        level: level,
        statusMessage: status_message
      }.compact

      return self if update_data.keys.size <= 1 # Only id is present

      @client.enqueue('observation-update', update_data)
      @data.merge!(update_data)

      self
    end
  end
end