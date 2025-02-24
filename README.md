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

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).