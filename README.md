# Langfuse Ruby Client

Ruby client for [Langfuse](https://github.com/langfuse/langfuse) - the open source LLM engineering platform

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'langfuse-rb'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install langfuse-rb
```

## Usage

### Basic Setup

```ruby
require 'langfuse'

# Initialize the Langfuse client
langfuse = Langfuse.new(
  public_key: 'pk-...',
  secret_key: 'sk-...',
  host: 'https://cloud.langfuse.com' # optional
)
```

### Tracing OpenAI Calls

```ruby
require 'langfuse'
require 'openai'

# Initialize OpenAI client
openai_client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])

# Wrap the OpenAI client with Langfuse tracing
traced_client = Langfuse::OpenAI.observe(openai_client)

# Use the traced client normally - all calls will be automatically traced
response = traced_client.chat(
  parameters: {
    model: "gpt-3.5-turbo",
    messages: [
      { role: "system", content: "You are a helpful assistant." },
      { role: "user", content: "Hello world" }
    ]
  }
)

# You can access the flushAsync method on the traced client
traced_client.flush_async
```

#### Auto-Flush Option

You can enable automatic flushing after each OpenAI call by setting the `auto_flush` option:

```ruby
# Create a traced client with auto-flush enabled
traced_client = Langfuse::OpenAI.observe(openai_client, {
  public_key: ENV['LANGFUSE_PUBLIC_KEY'],
  secret_key: ENV['LANGFUSE_SECRET_KEY'],
  auto_flush: true  # Will flush after each API call
})

# No need to call flush_async manually - it happens automatically after each call
response = traced_client.chat(parameters: { /* ... */ })
```

This is particularly useful in serverless environments or when you want to ensure data is sent to Langfuse immediately after each API call.

### Create traces manually

```ruby
# Create a trace
trace = langfuse.trace(
  name: "My Trace",
  user_id: "user-123",
  metadata: { source: "ruby-client" }
)

# Add a generation to the trace
generation = trace.generation(
  name: "Text Generation",
  model: "gpt-3.5-turbo",
  input: {
    messages: [
      { role: "system", content: "You are a helpful assistant." },
      { role: "user", content: "Hello world" }
    ]
  },
  output: "Hello! How can I help you today?",
  usage: {
    input: 20,
    output: 10,
    total: 30
  }
)

# Make sure to flush at the end of your process
langfuse.flush
```

### Thread Safety and Sidekiq Integration

When using Langfuse in multi-threaded environments like Sidekiq, the client provides thread-safe options to prevent deadlocks or recursive locking errors:

#### Using Thread-Local Clients

For Sidekiq workers, it's recommended to use thread-local clients to avoid sharing state between workers:

```ruby
class MyLLMWorker
  include Sidekiq::Worker

  def perform(user_id, query)
    # Get a thread-local client for this worker
    langfuse = Langfuse.thread_local_client(
      public_key: ENV['LANGFUSE_PUBLIC_KEY'],
      secret_key: ENV['LANGFUSE_SECRET_KEY']
    )

    # Create a trace
    trace = langfuse.trace(
      name: "Sidekiq LLM Query",
      user_id: user_id
    )

    # Your LLM logic here...

    # Explicitly flush before the worker completes
    langfuse.flush

    # Clear the thread-local client to free resources
    Langfuse.clear_thread_local_client
  end
end
```

#### Thread-Safe Configuration Options

The client supports options to improve thread safety:

```ruby
langfuse = Langfuse.new(
  public_key: 'pk-...',
  secret_key: 'sk-...',
  # Thread safety options
  disable_background_flush: true,   # Disable background flush timer (recommended for Sidekiq)
)
```

#### OpenAI Integration in Sidekiq

When using the OpenAI integration in Sidekiq, create a new traced client for each job:

```ruby
class OpenAIWorker
  include Sidekiq::Worker

  def perform(user_id, prompt)
    # Create a fresh OpenAI client for this job
    openai_client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])

    # Create a traced client with thread-safe options
    traced_client = Langfuse::OpenAI.observe(openai_client, {
      public_key: ENV['LANGFUSE_PUBLIC_KEY'],
      secret_key: ENV['LANGFUSE_SECRET_KEY'],
      user_id: user_id,
      disable_background_flush: true,  # Important for Sidekiq
      auto_flush: true  # Automatically flush after each API call
    })

    # Make the API call
    response = traced_client.chat(parameters: {
      model: "gpt-3.5-turbo",
      messages: [{ role: "user", content: prompt }]
    })

    # With auto_flush enabled, no need to call flush_async manually
  end
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
