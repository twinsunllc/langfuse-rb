require 'langfuse'
require 'openai'
require 'dotenv'

Dotenv.load

# Initialize the Langfuse client directly (not required if using configuration in observe)
langfuse = Langfuse.new(
  public_key: ENV['LANGFUSE_PUBLIC_KEY'],
  secret_key: ENV['LANGFUSE_SECRET_KEY'],
  host: ENV['LANGFUSE_HOST'] || 'https://cloud.langfuse.com'
)

# Initialize OpenAI client
openai_client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])

# Prepare the input for the first query
first_query_input = {
  messages: [
    { role: "system", content: "You are a helpful assistant." },
    { role: "user", content: "What is Ruby on Rails?" }
  ]
}

# Option 1: Wrap the OpenAI client with configuration
traced_client = Langfuse::OpenAI.observe(openai_client, {
  public_key: ENV['LANGFUSE_PUBLIC_KEY'],
  secret_key: ENV['LANGFUSE_SECRET_KEY'],
  host: ENV['LANGFUSE_HOST'] || 'https://cloud.langfuse.com',
  version: "1.0.0",
  release: "2023-02-26",
  level: Langfuse::ObservationLevel::DEFAULT,
  trace_name: "Rails Information Query",
  metadata: { source: "example script" }
})

# Use the traced client - all calls will be automatically traced
response = traced_client.chat(
  parameters: {
    model: "gpt-4o-mini",
    messages: first_query_input[:messages],
    temperature: 0.7
  }
)

puts "Response from OpenAI:"
puts response.dig('choices', 0, 'message', 'content')

# Option 2: Use an existing trace with explicit input/output
trace = langfuse.trace(
  name: "Multi-step conversation",
  version: "1.0.0",
  public_trace: true,
  input: { initial_query: "What is Ruby on Rails?" }
)

# Prepare the input for the follow-up query
follow_up_input = {
  messages: [
    { role: "system", content: "You are a helpful assistant." },
    { role: "user", content: "What is Ruby on Rails?" },
    { role: "assistant", content: response.dig('choices', 0, 'message', 'content') },
    { role: "user", content: "What are the main components of Rails?" }
  ]
}

# Create a traced client that uses the parent trace
traced_client2 = Langfuse::OpenAI.observe(openai_client, {
  parent_trace: trace,
  generation_name: "Rails Follow-up Question",
  level: Langfuse::ObservationLevel::DEFAULT
})

# Use the traced client with existing trace
response2 = traced_client2.chat(
  parameters: {
    model: "gpt-4o-mini",
    messages: follow_up_input[:messages],
    temperature: 0.7
  }
)

follow_up_response = response2.dig('choices', 0, 'message', 'content')
puts "\nFollow-up response:"
puts follow_up_response

# Update the trace with the final output
trace.update(
  output: {
    initial_response: response.dig('choices', 0, 'message', 'content'),
    follow_up_response: follow_up_response
  }
)

# Add a custom event to the trace
trace.event(
  name: "Conversation Completed",
  level: Langfuse::ObservationLevel::DEFAULT,
  metadata: {
    num_messages: follow_up_input[:messages].length,
    total_tokens: response2.dig('usage', 'total_tokens')
  }
)

# Make sure to flush before the program ends
traced_client.flush_async
langfuse.flush

puts "\nExample completed! Check your Langfuse dashboard."