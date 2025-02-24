RSpec.describe Langfuse::OpenAI do
  let(:mock_client) { double("OpenAI::Client") }
  
  describe ".observe" do
    it "returns a TracedOpenAIClient instance" do
      traced_client = Langfuse::OpenAI.observe(mock_client)
      expect(traced_client).to be_a(Langfuse::OpenAI::TracedOpenAIClient)
    end
  end
  
  describe ".parse_input_args" do
    it "extracts model, input, and parameters from chat parameters" do
      args = {
        parameters: {
          model: "gpt-3.5-turbo",
          messages: [
            { role: "user", content: "Hello" }
          ],
          temperature: 0.7,
          max_tokens: 100
        }
      }
      
      parsed = Langfuse::OpenAI.parse_input_args(args)
      
      expect(parsed[:model]).to eq("gpt-3.5-turbo")
      expect(parsed[:input][:messages]).to eq([{ role: "user", content: "Hello" }])
      expect(parsed[:model_parameters][:temperature]).to eq(0.7)
      expect(parsed[:model_parameters][:max_tokens]).to eq(100)
    end
    
    it "extracts model, input, and parameters from completion parameters" do
      args = {
        parameters: {
          model: "text-davinci-003",
          prompt: "Hello, how are you?",
          temperature: 0.5
        }
      }
      
      parsed = Langfuse::OpenAI.parse_input_args(args)
      
      expect(parsed[:model]).to eq("text-davinci-003")
      expect(parsed[:input]).to eq("Hello, how are you?")
      expect(parsed[:model_parameters][:temperature]).to eq(0.5)
    end
  end
  
  describe ".parse_completion_output" do
    it "extracts output text from chat completion response" do
      response = {
        choices: [
          {
            message: { content: "Hello! I'm an AI assistant." }
          }
        ]
      }
      
      output = Langfuse::OpenAI.parse_completion_output(response)
      expect(output).to eq({ content: "Hello! I'm an AI assistant." })
    end
    
    it "extracts output text from completion response" do
      response = {
        choices: [
          {
            text: "Hello! I'm an AI assistant."
          }
        ]
      }
      
      output = Langfuse::OpenAI.parse_completion_output(response)
      expect(output).to eq("Hello! I'm an AI assistant.")
    end
  end
  
  describe ".parse_usage" do
    it "extracts usage data from response" do
      response = {
        usage: {
          prompt_tokens: 10,
          completion_tokens: 20,
          total_tokens: 30
        }
      }
      
      usage = Langfuse::OpenAI.parse_usage(response)
      expect(usage).to eq({
        input: 10,
        output: 20,
        total: 30
      })
    end
    
    it "returns nil if usage is not available" do
      response = { choices: [] }
      usage = Langfuse::OpenAI.parse_usage(response)
      expect(usage).to be_nil
    end
  end
  
  describe Langfuse::OpenAI::TracedOpenAIClient do
    let(:traced_client) { Langfuse::OpenAI.observe(mock_client) }
    
    it "forwards method calls to the original client" do
      expect(mock_client).to receive(:models).and_return({ data: [] })
      expect(traced_client.models).to eq({ data: [] })
    end
    
    it "calls the chat method with parameters" do
      params = { model: "gpt-3.5-turbo", messages: [{ role: "user", content: "Hello" }] }
      expect(mock_client).to receive(:chat).with(parameters: params).and_return({ choices: [] })
      traced_client.chat(parameters: params)
    end
    
    it "checks method existence on the original client" do
      expect(mock_client).to receive(:respond_to?).with(:models, false).and_return(true)
      expect(traced_client.respond_to?(:models)).to be true
    end
  end
end