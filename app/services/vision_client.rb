# Coarse on-device perception via local Gemma 4 VISION (gemma4:e4b is multimodal).
# Mirrors GemmaClient — Ollama native POST /api/chat, think:false, format:"json" — plus an
# images:[<base64>] array. Asks ONLY qualitative questions (presence + a coarse band); it
# deliberately does NOT ask for a head-count (Gemma miscounts — verified in a spike).
#
# Returns a normalized coarse read Hash, or nil on any failure so the feature stays silently
# inert (camera off / Ollama down / unparseable → zero behavior change). Frames are never stored.
require "net/http"
require "json"
require "base64"

class VisionClient
  ENDPOINT = ENV.fetch("GEMMA_ENDPOINT", "http://localhost:11434")
  MODEL    = ENV.fetch("VISION_MODEL", "gemma4:e4b")

  LEVELS = %w[none light busy].freeze

  PROMPT = <<~PROMPT.freeze
    You are TurnPilot's on-device perception for a shop counter. Judge ONLY whether customers
    are waiting — do NOT count exact people. Reply with ONLY a JSON object (no prose):
      "people_present": boolean — is anyone visibly waiting at the counter?
      "queue_level": exactly one of "none", "light", "busy" — a coarse pressure band, never a number.
      "note": one short sentence describing what you see (no personal details).
  PROMPT

  # image: a file path OR an already-base64-encoded JPEG string.
  def self.observe(image)
    content = chat(base64_for(image))
    normalize(GemmaClient.parse_content(content)) # parse_content raises GemmaClient::Error if unparseable
  rescue GemmaClient::Error, Errno::ECONNREFUSED, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.warn("[VisionClient] #{e.class}: #{e.message}")
    nil
  end

  # Coerce Gemma's raw object into the strict coarse contract, with safe defaults:
  # absence of perception must never CREATE urgency.
  def self.normalize(obj)
    level = obj["queue_level"].to_s.strip.downcase
    level = "none" unless LEVELS.include?(level)
    {
      "people_present" => truthy(obj["people_present"]),
      "queue_level" => level,
      "note" => obj["note"].to_s.strip[0, 200].to_s
    }
  end

  def self.truthy(value)
    return value if [ true, false ].include?(value)

    %w[true yes 1 present waiting].include?(value.to_s.strip.downcase)
  end

  # Raw /api/chat vision call → message content string. Isolated so tests can stub it.
  def self.chat(base64_jpeg)
    res = post("/api/chat", {
      model: MODEL, stream: false, think: false, format: "json",
      messages: [ { role: "user", content: PROMPT, images: [ base64_jpeg ] } ],
      options: { temperature: 0 }
    })
    res.dig("message", "content")
  end

  def self.base64_for(image)
    if image.is_a?(String) && File.exist?(image)
      Base64.strict_encode64(File.binread(image))
    else
      image.to_s
    end
  end

  def self.post(path, body)
    uri = URI.join(ENDPOINT.sub(%r{/+$}, "") + "/", path.sub(%r{^/+}, ""))
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 120 # cold vision load can be ~7.6s
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req.body = JSON.dump(body)
    res = http.request(req)
    raise GemmaClient::Error, "Vision HTTP #{res.code}: #{res.body.to_s[0, 200]}" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body)
  end
  private_class_method :post
end
