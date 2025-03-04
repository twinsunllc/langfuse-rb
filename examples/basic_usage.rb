require 'langfuse'
require 'dotenv'

Dotenv.load

# Initialize the Langfuse client
langfuse = Langfuse.new(
  public_key: ENV['LANGFUSE_PUBLIC_KEY'],
  secret_key: ENV['LANGFUSE_SECRET_KEY'],
  host: ENV['LANGFUSE_HOST'] || 'https://cloud.langfuse.com'
)

# Define the input data
input_data = {
  messages: [
    { role: "system", content: "You are a helpful assistant." },
    { role: "user", content: "Tell me a joke about programming." }
  ]
}

# Define the output data
output_data = "Why do programmers prefer dark mode? Because light attracts bugs!"

# Create a trace with input
trace = langfuse.trace(
  name: "Example Trace",
  user_id: "user-123",
  metadata: { source: "ruby-example" },
  version: "1.0.0",
  release: "2023-02-26",
  input: input_data
)

# Add a generation to the trace
generation = trace.generation(
  name: "Example Generation",
  model: "gpt-3.5-turbo",
  input: input_data,
  output: output_data,
  usage: {
    input: 35,
    output: 15,
    total: 50
  },
  usage_details: {
    prompt_tokens: 35,
    completion_tokens: 15,
    total_tokens: 50
  },
  model_parameters: {
    temperature: 0.7,
    max_tokens: 100
  },
  level: Langfuse::ObservationLevel::DEFAULT
)

# Add a span to the trace
span = trace.span(
  name: "Data Processing Span",
  input: { data_size: 1000 },
  level: Langfuse::ObservationLevel::DEBUG
)

# Do some work...
sleep(0.5)

# Update the span when done
span.update(
  end_time: Time.now,
  metadata: { status: "completed" },
  output: { processed_items: 1000 }
)

# Add an event to the trace
trace.event(
  name: "Process Completed",
  level: Langfuse::ObservationLevel::DEFAULT,
  metadata: { duration_ms: 500 }
)

# Update the trace with the output
trace.update(
  output: {
    joke: output_data,
    processing_result: { processed_items: 1000 }
  }
)

# Make sure to flush before the program ends
langfuse.flush

puts "Example completed! Check your Langfuse dashboard."