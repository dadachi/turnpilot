require "test_helper"

# Offline: the raw /api/chat vision call (VisionClient.chat) is stubbed, so no Ollama needed.
class VisionClientTest < ActiveSupport::TestCase
  def stubbing(receiver, name, impl)
    original = receiver.singleton_method(name)
    receiver.define_singleton_method(name, impl)
    yield
  ensure
    receiver.define_singleton_method(name, original)
  end

  # --- normalize: the coarse contract, with safe defaults ---------------

  test "normalize passes a clean coarse read through" do
    out = VisionClient.normalize({ "people_present" => true, "queue_level" => "busy", "note" => "a line at the counter" })
    assert_equal true, out["people_present"]
    assert_equal "busy", out["queue_level"]
    assert_equal "a line at the counter", out["note"]
  end

  test "normalize clamps an unknown queue_level to none" do
    assert_equal "none", VisionClient.normalize({ "queue_level" => "slammed" })["queue_level"]
    assert_equal "none", VisionClient.normalize({ "queue_level" => 5 })["queue_level"]
  end

  test "normalize defaults missing keys to safe (no perception = no urgency)" do
    out = VisionClient.normalize({})
    assert_equal false, out["people_present"]
    assert_equal "none", out["queue_level"]
    assert_equal "", out["note"]
  end

  test "normalize coerces stringy booleans for people_present" do
    assert_equal true, VisionClient.normalize({ "people_present" => "yes" })["people_present"]
    assert_equal true, VisionClient.normalize({ "people_present" => "true" })["people_present"]
    assert_equal false, VisionClient.normalize({ "people_present" => "no" })["people_present"]
  end

  # --- observe: end-to-end with the HTTP call stubbed -------------------

  test "observe returns the normalized read on a good vision response" do
    stubbing(VisionClient, :chat, ->(*) { '{"people_present": true, "queue_level": "light", "note": "one person"}' }) do
      out = VisionClient.observe("/any/path.jpg")
      assert_equal({ "people_present" => true, "queue_level" => "light", "note" => "one person" }, out)
    end
  end

  test "observe extracts JSON even when wrapped in prose" do
    stubbing(VisionClient, :chat, ->(*) { "Sure: {\"people_present\": false, \"queue_level\": \"none\"} done" }) do
      assert_equal "none", VisionClient.observe("x")["queue_level"]
    end
  end

  test "observe returns nil (inert) on unparseable content" do
    stubbing(VisionClient, :chat, ->(*) { "camera unavailable, no json here" }) do
      assert_nil VisionClient.observe("x")
    end
  end

  test "observe returns nil (inert) when the vision call errors" do
    stubbing(VisionClient, :chat, ->(*) { raise GemmaClient::Error, "ollama down" }) do
      assert_nil VisionClient.observe("x")
    end
  end
end
