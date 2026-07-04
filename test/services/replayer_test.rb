require "test_helper"

class ReplayerTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 7, 4, 12, 0, 0)
  SHOP = "8f4c2b10-0000-4000-8000-000000000001".freeze

  # An order scripted to join at -10m, be prepared at +5m, completed at +12m.
  def scripted
    Order.create!(shop_id: SHOP, queue_number: "1", status: :waiting,
                  joined_at: NOW - 10.minutes, prepared_at: NOW + 5.minutes,
                  completed_at: NOW + 12.minutes)
  end

  test "advance materializes status from the timeline as the clock moves" do
    order = scripted

    Replayer.advance(NOW)
    assert order.reload.waiting?, "prep time not reached yet"

    Replayer.advance(NOW + 6.minutes)
    assert order.reload.prepared?, "past prepared_at"

    Replayer.advance(NOW + 13.minutes)
    assert order.reload.completed?, "past completed_at"
  end

  test "live scope hides not-yet-joined orders and completed ones" do
    future = Order.create!(shop_id: SHOP, queue_number: "9", status: :waiting,
                           joined_at: NOW + 3.minutes)
    joined = scripted

    live_ids = Order.live(NOW).pluck(:id)
    assert_includes live_ids, joined.id
    assert_not_includes live_ids, future.id, "future join hidden until due"

    assert_includes Order.live(NOW + 4.minutes).pluck(:id), future.id, "revealed once joined"
    assert_not_includes Order.live(NOW + 20.minutes).pluck(:id), joined.id, "completed drops out"
  end

  test "seed loads the rush with live, flagged orders at the anchor" do
    live = Replayer.seed(now: NOW)
    assert_operator live, :>, 0
    assert_operator Order.count, :>=, live, "future joins are stored but hidden"
    assert Order.live(NOW).any? { |o| o.flagged?(NOW) }, "anchor leaves at least one order past threshold"
  end

  test "seed resets each shop's learned threshold to baseline" do
    ShopThreshold.for(SHOP).update!(risk_multiplier: 3.0)
    Replayer.seed(now: NOW)
    assert_equal ShopThreshold::BASELINE, ShopThreshold.multiplier_for(SHOP), "fresh demo starts at baseline"
  end
end
