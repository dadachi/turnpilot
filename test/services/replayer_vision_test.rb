require "test_helper"

# P3: camera perception folded into walk-away generation. GemmaClient + broadcasts stubbed.
class ReplayerVisionTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 7, 5, 12, 0, 0)
  SHOP = "8f4c2b10-0000-4000-8000-000000000001".freeze
  ADVICE = { "advise" => true, "text" => "Check on the customer.", "rationale" => "waiting", "suggested_action" => "update_customer" }.freeze

  def stubbing(receiver, name, impl)
    original = receiver.singleton_method(name)
    receiver.define_singleton_method(name, impl)
    yield
  ensure
    receiver.define_singleton_method(name, original)
  end

  def with_stubs
    stubbing(GemmaClient, :advise, ->(*, **) { ADVICE }) do
      stubbing(Turbo::StreamsChannel, :broadcast_prepend_to, ->(*, **) { nil }) do
        yield
      end
    end
  end

  # Cooking 459s: risk 459 / (360*1.5=540) = 0.85 — past the 0.8 escalation line, NOT flagged.
  def borderline_cook
    Order.create!(status: :prepared, shop_id: SHOP, queue_number: "7",
                  joined_at: NOW - 500, prepared_at: NOW - 459)
  end

  def present(level: :light, at: NOW)
    VisionObservation.create!(shop_id: SHOP, observed_at: at, queue_level: level, people_present: true)
  end

  test "a borderline cook does NOT advise without a present-customer signal" do
    borderline_cook
    with_stubs { assert_empty Replayer.walk_away(NOW, 3) }
  end

  test "a borderline cook DOES advise when the camera sees a waiting customer" do
    borderline_cook
    present
    with_stubs do
      advisories = Replayer.walk_away(NOW, 3)
      assert_equal 1, advisories.size
      assert_equal "walk_away_risk", advisories.first.kind
    end
  end

  test "a stale present-signal does not escalate" do
    borderline_cook
    present(at: NOW - (VisionObservation::FRESH_WINDOW + 1.minute))
    with_stubs { assert_empty Replayer.walk_away(NOW, 3) }
  end

  test "an already-flagged cook still advises regardless of the camera" do
    Order.create!(status: :prepared, shop_id: SHOP, queue_number: "8",
                  joined_at: NOW - 700, prepared_at: NOW - 660) # 660s > 540 → flagged
    with_stubs { assert_equal 1, Replayer.walk_away(NOW, 3).size }
  end
end
