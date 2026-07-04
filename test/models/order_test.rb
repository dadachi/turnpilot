require "test_helper"

class OrderTest < ActiveSupport::TestCase
  # Fixed reference time so every case is deterministic (no wall-clock flake).
  NOW = Time.utc(2026, 7, 4, 12, 0, 0)

  # Flag threshold = BASELINE_PREP_SECONDS * RISK_THRESHOLD = 360 * 1.5 = 540s (9 min).
  THRESHOLD = Order::BASELINE_PREP_SECONDS * Order::RISK_THRESHOLD

  def waiting(seconds_ago)
    Order.new(status: :waiting, joined_at: NOW - seconds_ago)
  end

  # --- wait_seconds -------------------------------------------------------

  test "wait_seconds counts from joined_at while waiting" do
    assert_equal 300, waiting(300).wait_seconds(NOW)
  end

  test "wait_seconds freezes at prepared_at once prepared" do
    order = Order.new(status: :prepared, joined_at: NOW - 600, prepared_at: NOW - 200)
    # 400s elapsed before prep, and it must not keep growing after NOW.
    assert_equal 400, order.wait_seconds(NOW)
    assert_equal 400, order.wait_seconds(NOW + 999)
  end

  test "wait_seconds is 0 for a completed order" do
    order = Order.new(status: :completed, joined_at: NOW - 600, completed_at: NOW - 100)
    assert_equal 0, order.wait_seconds(NOW)
  end

  # --- walk_away_risk -----------------------------------------------------

  test "walk_away_risk is 0 unless waiting" do
    assert_equal 0.0, Order.new(status: :prepared, joined_at: NOW - 600).walk_away_risk(NOW)
    assert_equal 0.0, Order.new(status: :completed, joined_at: NOW - 600).walk_away_risk(NOW)
  end

  test "walk_away_risk is wait over the threshold window, rounded" do
    # 270s / 540s = 0.5
    assert_in_delta 0.5, waiting(270).walk_away_risk(NOW), 0.001
    # at the threshold it reads exactly 1.0
    assert_in_delta 1.0, waiting(THRESHOLD.to_i).walk_away_risk(NOW), 0.001
  end

  # --- flagged? (the demo trigger) ---------------------------------------

  test "flagged? is false at or below the threshold" do
    assert_not waiting(THRESHOLD.to_i - 1).flagged?(NOW)
    assert_not waiting(THRESHOLD.to_i).flagged?(NOW), "boundary is strictly greater-than"
  end

  test "flagged? is true just past the threshold" do
    assert waiting(THRESHOLD.to_i + 1).flagged?(NOW)
  end

  test "flagged? is false for non-waiting orders regardless of elapsed time" do
    long_ago = NOW - 3600
    assert_not Order.new(status: :prepared, joined_at: long_ago, prepared_at: NOW).flagged?(NOW)
    assert_not Order.new(status: :completed, joined_at: long_ago, completed_at: NOW).flagged?(NOW)
  end

  # --- wait_minutes -------------------------------------------------------

  test "wait_minutes converts seconds to minutes rounded to 0.1" do
    assert_in_delta 5.0, waiting(300).wait_minutes(NOW), 0.001
    assert_in_delta 1.5, waiting(90).wait_minutes(NOW), 0.001
  end
end
