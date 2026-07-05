require "test_helper"

class WalkedAwayAdvisorTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 7, 5, 12, 0, 0)
  SHOP = "8f4c2b10-0000-4000-8000-000000000001".freeze
  ADVICE = { "advise" => true, "text" => "Re-notify the customer.", "rationale" => "left", "suggested_action" => "re_notify_customer" }.freeze

  def stubbing(receiver, name, impl)
    original = receiver.singleton_method(name)
    receiver.define_singleton_method(name, impl)
    yield
  ensure
    receiver.define_singleton_method(name, original)
  end

  def with_gemma(result)
    stubbing(GemmaClient, :advise, ->(*, **) { result }) do
      stubbing(Turbo::StreamsChannel, :broadcast_prepend_to, ->(*, **) { nil }) do
        yield
      end
    end
  end

  # present -> absent -> absent across three frames (5s apart), i.e. a debounced departure.
  def departure_frames
    VisionObservation.create!(shop_id: SHOP, observed_at: NOW - 10, queue_level: :light, people_present: true)
    VisionObservation.create!(shop_id: SHOP, observed_at: NOW - 5,  queue_level: :none,  people_present: false)
    VisionObservation.create!(shop_id: SHOP, observed_at: NOW,      queue_level: :none,  people_present: false)
  end

  # A flagged (overrunning) cooking order.
  def flagged_cook
    Order.create!(status: :prepared, shop_id: SHOP, queue_number: "7",
                  joined_at: NOW - 700, prepared_at: NOW - 660) # 660s > 540 flag window
  end

  test "advises when a customer left AND a flagged order is still cooking" do
    departure_frames
    flagged_cook
    with_gemma(ADVICE) do
      advisory = nil
      assert_difference -> { Advisory.count }, 1 do
        advisory = WalkedAwayAdvisor.for(SHOP, now: NOW)
      end
      assert_equal "walked_away", advisory.kind
      assert_nil advisory.order
    end
  end

  test "stays quiet without a flagged order cooking" do
    departure_frames # customer left, but nothing is overrunning
    with_gemma(ADVICE) { assert_nil WalkedAwayAdvisor.for(SHOP, now: NOW) }
  end

  test "does not fire on a single absent frame (debounce needs two)" do
    VisionObservation.create!(shop_id: SHOP, observed_at: NOW - 10, queue_level: :light, people_present: true)
    VisionObservation.create!(shop_id: SHOP, observed_at: NOW - 5,  queue_level: :light, people_present: true)
    VisionObservation.create!(shop_id: SHOP, observed_at: NOW,      queue_level: :none,  people_present: false)
    flagged_cook
    with_gemma(ADVICE) { assert_nil WalkedAwayAdvisor.for(SHOP, now: NOW) }
  end

  test "stays quiet when nobody was ever present" do
    3.times { |i| VisionObservation.create!(shop_id: SHOP, observed_at: NOW - (i * 5), queue_level: :none, people_present: false) }
    flagged_cook
    with_gemma(ADVICE) { assert_nil WalkedAwayAdvisor.for(SHOP, now: NOW) }
  end

  test "suppresses a repeat within the window" do
    departure_frames
    flagged_cook
    with_gemma(ADVICE) do
      assert_not_nil WalkedAwayAdvisor.for(SHOP, now: NOW)
      assert_nil WalkedAwayAdvisor.for(SHOP, now: NOW)
    end
  end
end
