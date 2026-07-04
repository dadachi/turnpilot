# Reasoning on local Gemma 4 via Ollama's NATIVE /api/chat (offline, on-device).
# Gemma 4 is a reasoning model: `think: false` disables chain-of-thought (else the
# visible content comes back empty); `format: "json"` forces clean, parseable JSON.
# The OpenAI /v1 endpoint can't disable thinking, so we use /api/chat.
require "net/http"
require "json"

class GemmaClient
  ENDPOINT = ENV.fetch("GEMMA_ENDPOINT", "http://localhost:11434")
  MODEL    = ENV.fetch("GEMMA_MODEL", "gemma4:e4b")

  Error = Class.new(StandardError)

  # Returns a parsed Hash (the model's JSON object). Raises GemmaClient::Error on failure.
  def self.advise(prompt, num_predict: 400, temperature: 0.2)
    new.advise(prompt, num_predict:, temperature:)
  end

  def advise(prompt, num_predict: 400, temperature: 0.2)
    res = post("/api/chat", {
      model: MODEL, stream: false, think: false, format: "json",
      messages: [ { role: "user", content: prompt } ],
      options: { temperature:, num_predict: }
    })
    self.class.parse_content(res.dig("message", "content"))
  end

  # Extract the JSON object from Gemma's message content. Even with format:"json", the
  # content can carry surrounding text/fences, so grab the outermost {...}. Raises
  # GemmaClient::Error on anything unparseable.
  def self.parse_content(content)
    text = content.to_s
    JSON.parse(text[/\{.*\}/m] || text)
  rescue JSON::ParserError => e
    raise Error, "unparseable advisory JSON: #{e.message} (raw: #{text[0, 200]})"
  end

  private

  def post(path, body)
    uri = URI.join(ENDPOINT.sub(%r{/+$}, "") + "/", path.sub(%r{^/+}, ""))
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 120
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req.body = JSON.dump(body)
    res = http.request(req)
    unless res.is_a?(Net::HTTPSuccess)
      raise Error, "Gemma HTTP #{res.code}: #{res.body.to_s[0, 300]}"
    end
    JSON.parse(res.body)
  end
end
