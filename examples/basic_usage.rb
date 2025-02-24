require 'langfuse'

# Initialize the Langfuse client
langfuse = Langfuse.new(
  public_key: ENV['LANGFUSE_PUBLIC_KEY'],
  secret_key: ENV['LANGFUSE_SECRET_KEY'],
  host: ENV['LANGFUSE_HOST'] || 'https://cloud.langfuse.com'
)

# Create a trace
trace = langfuse.trace(
  name: "Example Trace",
  user_id: "user-123",
  metadata: { source: "ruby-example" }
)

# Add a generation to the trace
generation = trace.generation(
  name: "Example Generation",
  model: "gpt-3.5-turbo",
  input: {
    messages: [
      { role: "system", content: "You are a helpful assistant." },
      { role: "user", content: "Tell me a joke about programming." }
    ]
  },
  output: "Why do programmers prefer dark mode? Because light attracts bugs!",
  usage: {
    input: 35,
    output: 15,
    total: 50
  }
)

# Add a span to the trace
span = trace.span(
  name: "Data Processing Span"
)

# Do some work...
sleep(0.5)

# Update the span when done
span.update(
  end_time: Time.now,
  metadata: { status: "completed" }
)

# Make sure to flush before the program ends
langfuse.flush

puts "Example completed! Check your Langfuse dashboard."