RSpec.describe Langfuse::Core do
  let(:client) do
    Langfuse::Core.new(
      public_key: 'pk-test',
      secret_key: 'sk-test',
      host: 'https://cloud.langfuse.com'
    )
  end

  before do
    # Stop the flush timer to avoid background thread issues in tests
    client.send(:stop_flush_timer)
  end

  describe "#trace" do
    it "creates a new trace with the specified name" do
      trace = client.trace(name: "Test Trace")
      expect(trace).to be_a(Langfuse::Trace)
      expect(trace.name).to eq("Test Trace")
    end

    it "uses custom ID if provided" do
      trace = client.trace(name: "Test Trace", id: "custom-id")
      expect(trace.id).to eq("custom-id")
    end

    it "creates a trace with user_id and session_id" do
      trace = client.trace(
        name: "Test Trace",
        user_id: "user-123",
        session_id: "session-456"
      )

      expect(trace.data[:userId]).to eq("user-123")
      expect(trace.data[:sessionId]).to eq("session-456")
    end

    it "creates a trace with metadata and tags" do
      metadata = { source: "test" }
      tags = ["test", "trace"]

      trace = client.trace(
        name: "Test Trace",
        metadata: metadata,
        tags: tags
      )

      expect(trace.data[:metadata]).to eq(metadata)
      expect(trace.data[:tags]).to eq(tags)
    end

    it "creates a trace with input and output" do
      input = { query: "What is the capital of France?" }
      output = "The capital of France is Paris."

      trace = client.trace(
        name: "Test Trace",
        input: input,
        output: output
      )

      expect(trace.data[:input]).to eq(input)
      expect(trace.data[:output]).to eq(output)
    end
  end

  describe "#enqueue" do
    it "adds an event to the queue" do
      client.enqueue("trace", { id: "test-id", name: "Test" })
      expect(client.queue.size).to eq(1)
      expect(client.queue[0][:type]).to eq("trace")
      expect(client.queue[0][:body][:id]).to eq("test-id")
    end

    it "respects sample rate" do
      client_with_sampling = Langfuse::Core.new(
        public_key: 'pk-test',
        secret_key: 'sk-test',
        host: 'https://cloud.langfuse.com',
        sample_rate: 0.0 # 0% sampling rate
      )

      client_with_sampling.send(:stop_flush_timer)

      result = client_with_sampling.enqueue("trace", { id: "test-id", name: "Test" })
      expect(result).to be false
      expect(client_with_sampling.queue.size).to eq(0)
    end

    it "flushes when queue size reaches flush_at" do
      client_with_small_batch = Langfuse::Core.new(
        public_key: 'pk-test',
        secret_key: 'sk-test',
        host: 'https://cloud.langfuse.com',
        flush_at: 2
      )

      client_with_small_batch.send(:stop_flush_timer)

      expect(client_with_small_batch).to receive(:flush).once

      client_with_small_batch.enqueue("trace", { id: "test-id-1", name: "Test" })
      client_with_small_batch.enqueue("trace", { id: "test-id-2", name: "Test" })
    end
  end

  describe "Trace" do
    let(:trace) { client.trace(name: "Test Trace") }

    describe "#generation" do
      it "creates a generation linked to the trace" do
        generation = trace.generation(
          model: "gpt-3.5-turbo",
          input: { messages: [{ role: "user", content: "Hello" }] },
          output: "Hi there!"
        )

        expect(generation).to be_a(Langfuse::Generation)
        expect(generation.trace_id).to eq(trace.id)
        expect(client.queue.size).to eq(2) # One for trace, one for generation
      end

      it "supports usage statistics" do
        usage = { input: 10, output: 20, total: 30 }

        generation = trace.generation(
          model: "gpt-3.5-turbo",
          input: "Hello",
          output: "Hi there!",
          usage: usage
        )

        expect(generation.data[:usage]).to eq(usage)
      end
    end

    describe "#span" do
      it "creates a span linked to the trace" do
        span = trace.span(name: "Test Span")

        expect(span).to be_a(Langfuse::Span)
        expect(span.trace_id).to eq(trace.id)
        expect(client.queue.size).to eq(2) # One for trace, one for span
      end
    end

    describe "#update" do
      it "updates trace properties" do
        trace.update(user_id: "new-user", metadata: { updated: true })

        expect(trace.data[:userId]).to eq("new-user")
        expect(trace.data[:metadata]).to eq({ updated: true })
        expect(client.queue.size).to eq(2) # One for trace, one for update
      end

      it "updates trace input and output" do
        input = { query: "What is the capital of France?" }
        output = "The capital of France is Paris."

        trace.update(input: input, output: output)

        expect(trace.data[:input]).to eq(input)
        expect(trace.data[:output]).to eq(output)
        expect(client.queue.size).to eq(2) # One for trace, one for update
      end

      it "doesn't create an event if no properties are changed" do
        trace.update()
        expect(client.queue.size).to eq(1) # Just the original trace
      end
    end
  end
end