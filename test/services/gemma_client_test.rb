require "test_helper"

# Covers the load-bearing bit that runs offline: extracting the advisory JSON object from
# Gemma's message content (which can arrive wrapped in text/fences even with format:"json").
# The HTTP call itself isn't exercised here — that needs a live Ollama.
class GemmaClientTest < ActiveSupport::TestCase
  test "parses a clean JSON object" do
    result = GemmaClient.parse_content('{"advise": true, "text": "go"}')
    assert_equal true, result["advise"]
    assert_equal "go", result["text"]
  end

  test "extracts the object when wrapped in prose or code fences" do
    wrapped = "Sure! ```json\n{\"advise\": false, \"text\": \"wait\"}\n``` hope that helps"
    result = GemmaClient.parse_content(wrapped)
    assert_equal false, result["advise"]
    assert_equal "wait", result["text"]
  end

  test "raises GemmaClient::Error on unparseable content" do
    assert_raises(GemmaClient::Error) { GemmaClient.parse_content("no json here") }
    assert_raises(GemmaClient::Error) { GemmaClient.parse_content(nil) }
    assert_raises(GemmaClient::Error) { GemmaClient.parse_content("{broken") }
  end
end
