require "test_helper"

class OrderTest < ActiveSupport::TestCase
  # Fixed reference time so every case is deterministic (no wall-clock flake).
  NOW = Time.utc(2026, 7, 4, 12, 0, 0)

  # Flag window = BASELINE_COOK_SECONDS * RISK_THRESHOLD = 360 * 1.5 = 540s (9 min).
  THRESHOLD = Order::BASELINE_COOK_SECONDS * Order::RISK_THRESHOLD

  # An order that started cooking `seconds_ago` and hasn't completed.
  def cooking(seconds_ago)
    Order.new(status: :prepared, prepared_at: NOW - seconds_ago)
  end

  # --- cook_seconds -------------------------------------------------------

  test "cook_seconds counts from prepared_at while cooking" do
    assert_equal 300, cooking(300).cook_seconds(NOW)
  end

  test "cook_seconds freezes at completed_at once cooking finishes" do
    order = Order.new(status: :completed, prepared_at: NOW - 600, completed_at: NOW - 200)
    # 400s of cooking, and it must not keep growing after completion.
    assert_equal 400, order.cook_seconds(NOW)
    assert_equal 400, order.cook_seconds(NOW + 999)
  end

  test "cook_seconds is 0 before cooking has started" do
    assert_equal 0, Order.new(status: :waiting, joined_at: NOW - 600).cook_seconds(NOW)
    assert_equal 0, Order.new(status: :prepared, prepared_at: NOW + 60).cook_seconds(NOW), "not started yet"
  end

  test "cook_seconds counts up to now while a future completion is still scripted" do
    # Replay: still cooking at NOW, but completed_at is a future scripted time.
    order = Order.new(status: :prepared, prepared_at: NOW - 300, completed_at: NOW + 120)
    assert_equal 300, order.cook_seconds(NOW), "counts to now, not the scripted completion"
  end

  # --- walk_away_risk -----------------------------------------------------

  test "walk_away_risk is 0 unless actively cooking" do
    assert_equal 0.0, Order.new(status: :waiting, joined_at: NOW - 600).walk_away_risk(NOW)
    assert_equal 0.0, Order.new(status: :completed, prepared_at: NOW - 600, completed_at: NOW - 60).walk_away_risk(NOW)
  end

  test "walk_away_risk is cook time over the threshold window, rounded" do
    assert_in_delta 0.5, cooking(270).walk_away_risk(NOW), 0.001            # 270/540
    assert_in_delta 1.0, cooking(THRESHOLD.to_i).walk_away_risk(NOW), 0.001 # at threshold
  end

  test "a shorter baseline raises the risk (cooks look slower)" do
    order = cooking(300)
    assert order.walk_away_risk(NOW, baseline: 120) > order.walk_away_risk(NOW)
  end

  # --- flagged? (the demo trigger) ---------------------------------------

  test "flagged? is false at or below the threshold" do
    assert_not cooking(THRESHOLD.to_i - 1).flagged?(NOW)
    assert_not cooking(THRESHOLD.to_i).flagged?(NOW), "boundary is strictly greater-than"
  end

  test "flagged? is true just past the threshold" do
    assert cooking(THRESHOLD.to_i + 1).flagged?(NOW)
  end

  test "flagged? is false for not-cooking orders regardless of elapsed time" do
    assert_not Order.new(status: :waiting, joined_at: NOW - 3600).flagged?(NOW), "not cooking yet"
    done = Order.new(status: :completed, prepared_at: NOW - 3600, completed_at: NOW - 1800)
    assert_not done.flagged?(NOW), "already completed"
  end

  test "a raised (learned) threshold un-flags a borderline cook" do
    order = cooking(600) # 10 min cooking: past baseline 540s, under a 720s (×2.0) window
    assert order.flagged?(NOW), "flagged at the baseline multiplier"
    assert_not order.flagged?(NOW, threshold: 2.0), "not flagged once the shop threshold is raised"
    assert order.walk_away_risk(NOW) > order.walk_away_risk(NOW, threshold: 2.0)
  end

  # --- suppressed? (override quiets similar advisories) -------------------

  test "suppressed? is true only for a recent same-kind override" do
    order = Order.create!(status: :prepared, prepared_at: NOW - 600, queue_number: "7")

    assert_not order.suppressed?, "no advisories yet"

    a = order.advisories.create!(kind: "walk_away_risk", status: :overridden, text: "x")
    assert order.suppressed?, "recent override suppresses"

    a.update_column(:created_at, (Advisory::SUPPRESSION_WINDOW + 1.minute).ago)
    assert_not order.suppressed?, "override older than the window no longer suppresses"
  end

  test "suppressed? ignores accepted advisories and other kinds" do
    order = Order.create!(status: :prepared, prepared_at: NOW - 600, queue_number: "8")
    order.advisories.create!(kind: "walk_away_risk", status: :accepted, text: "ok")
    order.advisories.create!(kind: "open_server", status: :overridden, text: "other")
    assert_not order.suppressed?
  end

  # --- baseline_cook_seconds (per-shop, learned from history) -------------

  SHOP = "8f4c2b10-0000-4000-8000-000000000001".freeze

  test "baseline_cook_seconds falls back to the constant without enough samples" do
    Order.create!(status: :completed, shop_id: SHOP, prepared_at: NOW - 600, completed_at: NOW - 300)
    assert_equal Order::BASELINE_COOK_SECONDS, Order.baseline_cook_seconds(SHOP), "1 sample < min"
  end

  test "baseline_cook_seconds averages recent completed cook durations for the shop" do
    [ 300, 360, 420 ].each_with_index do |dur, i|
      Order.create!(status: :completed, shop_id: SHOP, queue_number: i.to_s,
                    prepared_at: NOW - dur, completed_at: NOW) # cook duration = dur
    end
    assert_equal 360, Order.baseline_cook_seconds(SHOP) # (300+360+420)/3
  end

  test "baseline_cook_seconds ignores other shops" do
    3.times do |i|
      Order.create!(status: :completed, shop_id: "other", queue_number: i.to_s,
                    prepared_at: NOW - 120, completed_at: NOW)
    end
    assert_equal Order::BASELINE_COOK_SECONDS, Order.baseline_cook_seconds(SHOP)
  end

  # --- cook_minutes -------------------------------------------------------

  test "cook_minutes converts seconds to minutes rounded to 0.1" do
    assert_in_delta 5.0, cooking(300).cook_minutes(NOW), 0.001
    assert_in_delta 1.5, cooking(90).cook_minutes(NOW), 0.001
  end
end
