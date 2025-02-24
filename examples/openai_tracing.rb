require 'langfuse'
require 'openai'

# Initialize the Langfuse client directly (not required if using configuration in observe)
langfuse = Langfuse.new(
  public_key: ENV['LANGFUSE_PUBLIC_KEY'],
  secret_key: ENV['LANGFUSE_SECRET_KEY'],
  host: ENV['LANGFUSE_HOST'] || 'https://cloud.langfuse.com'
)

# Initialize OpenAI client
openai_client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])

# Option 1: Wrap the OpenAI client with configuration
traced_client = Langfuse::OpenAI.observe(openai_client, {
  public_key: ENV['LANGFUSE_PUBLIC_KEY'],
  secret_key: ENV['LANGFUSE_SECRET_KEY'],
  host: ENV['LANGFUSE_HOST'] || 'https://cloud.langfuse.com'
})

# Use the traced client - all calls will be automatically traced
response = traced_client.chat(
  parameters: {
    model: "gpt-3.5-turbo",
    messages: [
      { role: "system", content: "You are a helpful assistant." },
      { role: "user", content: "What is Ruby on Rails?" }
    ],
    temperature: 0.7
  }
)

puts "Response from OpenAI:"
puts response.dig(:choices, 0, :message, :content)

# Option 2: Use an existing trace
trace = langfuse.trace(name: "Multi-step conversation")

# Create a traced client that uses the parent trace
traced_client2 = Langfuse::OpenAI.observe(openai_client, {
  parent_trace: trace,
  generation_name: "Rails Follow-up Question"
})

# Use the traced client with existing trace
response2 = traced_client2.chat(
  parameters: {
    model: "gpt-3.5-turbo",
    messages: [
      { role: "system", content: "You are a helpful assistant." },
      { role: "user", content: "What is Ruby on Rails?" },
      { role: "assistant", content: response.dig(:choices, 0, :message, :content) },
      { role: "user", content: "What are the main components of Rails?" }
    ],
    temperature: 0.7
  }
)

puts "\nFollow-up response:"
puts response2.dig(:choices, 0, :message, :content)

# Make sure to flush before the program ends
traced_client.flush_async

puts "\nExample completed! Check your Langfuse dashboard."