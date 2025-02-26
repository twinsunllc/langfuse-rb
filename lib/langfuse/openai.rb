require 'singleton'
require 'openai'

module Langfuse
  module OpenAI
    # Singleton for managing Langfuse client
    class LangfuseSingleton
      include Singleton

      attr_accessor :client

      # Get or initialize the Langfuse client
      # @param options [Hash] Client initialization options
      # @return [Langfuse::Core] Langfuse client
      def self.get_instance(options = {})
        if instance.client.nil? && options.key?(:public_key) && options.key?(:secret_key)
          instance.client = Langfuse.new(
            public_key: options[:public_key],
            secret_key: options[:secret_key],
            host: options[:host] || 'https://cloud.langfuse.com',
            **options
          )
        end

        instance.client
      end
    end

    # Create a Langfuse-traced OpenAI client wrapper
    # @param client [OpenAI::Client] OpenAI client
    # @param config [Hash] Configuration options
    # @return [TracedOpenAIClient] Traced OpenAI client
    def self.observe(client, config = {})
      TracedOpenAIClient.new(client, config)
    end

    # Helper to parse OpenAI input args
    # @param args [Hash] OpenAI method arguments
    # @return [Hash] Parsed arguments with model, input and parameters
    def self.parse_input_args(args)
      params = {
        frequency_penalty: args[:parameters]&.fetch(:frequency_penalty, nil),
        logit_bias: args[:parameters]&.fetch(:logit_bias, nil),
        max_tokens: args[:parameters]&.fetch(:max_tokens, nil),
        n: args[:parameters]&.fetch(:n, nil),
        presence_penalty: args[:parameters]&.fetch(:presence_penalty, nil),
        seed: args[:parameters]&.fetch(:seed, nil),
        stop: args[:parameters]&.fetch(:stop, nil),
        stream: args[:parameters]&.fetch(:stream, nil),
        temperature: args[:parameters]&.fetch(:temperature, nil),
        top_p: args[:parameters]&.fetch(:top_p, nil),
        user: args[:parameters]&.fetch(:user, nil),
        response_format: args[:parameters]&.fetch(:response_format, nil)
      }.compact

      # Extract model
      model = args[:parameters]&.fetch(:model, nil)

      # Extract input
      input = if args[:parameters]&.key?(:messages)
        {
          messages: args[:parameters][:messages],
          functions: args[:parameters][:functions],
          function_call: args[:parameters][:function_call],
          tools: args[:parameters][:tools],
          tool_choice: args[:parameters][:tool_choice]
        }.compact
      else
        args[:parameters]&.fetch(:prompt, nil)
      end

      {
        model: model,
        input: input,
        model_parameters: params
      }
    end

    # Helper to parse completion output
    # @param response [Hash] OpenAI API response
    # @return [String] Completion text
    def self.parse_completion_output(response)
      return "" unless response.is_a?(Hash) && response.key?(:choices) && response[:choices].is_a?(Array)

      if response[:choices][0].key?(:message)
        response[:choices][0][:message]
      else
        response[:choices][0][:text] || ""
      end
    end

    # Helper to parse usage statistics
    # @param response [Hash] OpenAI API response
    # @return [Hash, nil] Usage statistics if available
    def self.parse_usage(response)
      return nil unless response.is_a?(Hash) && response.key?(:usage)

      usage = response[:usage]
      {
        input: usage[:prompt_tokens],
        output: usage[:completion_tokens],
        total: usage[:total_tokens]
      }
    end

    # Helper to parse usage details in the new format
    # @param response [Hash] OpenAI API response
    # @return [Hash, nil] Usage details if available
    def self.parse_usage_details(response)
      return nil unless response.is_a?(Hash) && response.key?(:usage)

      usage = response[:usage]
      {
        prompt_tokens: usage[:prompt_tokens],
        completion_tokens: usage[:completion_tokens],
        total_tokens: usage[:total_tokens]
      }
    end

    # Class representing a traced OpenAI client
    class TracedOpenAIClient
      # Initialize a new traced client
      # @param client [OpenAI::Client] Original OpenAI client
      # @param config [Hash] Configuration options
      def initialize(client, config = {})
        @client = client
        @config = config

        # Initialize the Langfuse client if config is provided
        if config[:public_key] && config[:secret_key]
          LangfuseSingleton.get_instance(config)
        end
      end

      # Wrapper for chat completions
      # @param parameters [Hash] Method parameters
      # @return [Hash] OpenAI API response
      def chat(parameters: {})
        trace_method(:chat, { parameters: parameters })
      end

      # Wrapper for completions
      # @param parameters [Hash] Method parameters
      # @return [Hash] OpenAI API response
      def completions(parameters: {})
        trace_method(:completions, { parameters: parameters })
      end

      # Wrapper for embeddings
      # @param parameters [Hash] Method parameters
      # @return [Hash] OpenAI API response
      def embeddings(parameters: {})
        trace_method(:embeddings, { parameters: parameters })
      end

      # Flush the Langfuse client
      def flush_async
        langfuse_client = get_langfuse_client
        langfuse_client&.flush_async
      end

      # Shutdown the Langfuse client
      def shutdown_async
        langfuse_client = get_langfuse_client
        langfuse_client&.shutdown
      end

      # Forward unknown methods to the original client
      def method_missing(method, *args, &block)
        if @client.respond_to?(method)
          @client.public_send(method, *args, &block)
        else
          super
        end
      end

      # Check if the client responds to a method
      def respond_to_missing?(method, include_private = false)
        @client.respond_to?(method, include_private) || super
      end

      private

      # Trace an OpenAI method call
      # @param method [Symbol] Method name
      # @param args [Hash] Method arguments
      # @return [Hash] Method response
      def trace_method(method, args)
        parsed_args = Langfuse::OpenAI.parse_input_args(args)

        # Create a trace if no parent specified
        langfuse_client = get_langfuse_client
        unless langfuse_client
          if method == :chat || method == :completions || method == :embeddings
            return @client.public_send(method, parameters: args[:parameters])
          else
            return @client.public_send(method, args)
          end
        end

        trace_config = {
          name: @config[:trace_name] || "OpenAI.#{method}",
          user_id: @config[:user_id],
          session_id: @config[:session_id],
          metadata: @config[:metadata],
          version: @config[:version],
          release: @config[:release],
          public_trace: @config[:public_trace]
        }.compact

        # Use existing trace or create new one
        trace = if @config[:parent_trace]
          @config[:parent_trace]
        else
          langfuse_client.trace(**trace_config)
        end

        generation_name = @config[:generation_name] || "OpenAI.#{method}"
        start_time = Time.now

        begin
          # Call the original OpenAI method, passing the parameters correctly
          response = if method == :chat || method == :completions || method == :embeddings
            @client.public_send(method, parameters: args[:parameters])
          else
            @client.public_send(method, args)
          end

          # Handle streaming responses
          if args[:parameters]&.fetch(:stream, false)
            # For simplicity, this implementation doesn't handle streaming
            # In a full implementation, you'd need to wrap the stream and collect chunks
            return response
          end

          # Parse the output and usage
          output = Langfuse::OpenAI.parse_completion_output(response)
          usage = Langfuse::OpenAI.parse_usage(response)
          usage_details = Langfuse::OpenAI.parse_usage_details(response)

          # Create a generation with all the new fields
          trace.generation(
            name: generation_name,
            model: parsed_args[:model],
            input: parsed_args[:input],
            output: output,
            start_time: start_time,
            end_time: Time.now,
            completion_start_time: nil, # OpenAI doesn't provide this
            model_parameters: parsed_args[:model_parameters],
            usage: usage,
            usage_details: usage_details,
            level: @config[:level] || Langfuse::ObservationLevel::DEFAULT,
            status_message: nil,
            version: @config[:version]
          )

          # Update the trace if not using a parent trace
          trace.update(metadata: { output: output }) unless @config[:parent_trace]

          response

        rescue => e
          # Create an error generation
          trace.generation(
            name: generation_name,
            model: parsed_args[:model],
            input: parsed_args[:input],
            start_time: start_time,
            end_time: Time.now,
            model_parameters: parsed_args[:model_parameters],
            level: Langfuse::ObservationLevel::ERROR,
            status_message: e.message,
            metadata: {
              error: e.message,
              error_type: e.class.name
            }
          )

          raise e
        end
      end

      # Get the Langfuse client
      # @return [Langfuse::Core, nil] Langfuse client
      def get_langfuse_client
        if @config[:parent]
          @config[:parent].client
        else
          LangfuseSingleton.get_instance(@config)
        end
      end
    end
  end
end