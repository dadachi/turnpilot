require "test_helper"

class ShopThresholdTest < ActiveSupport::TestCase
  SHOP = "8f4c2b10-0000-4000-8000-000000000001".freeze

  test ".for creates a baseline threshold and is idempotent per shop" do
    t = ShopThreshold.for(SHOP)
    assert_equal ShopThreshold::BASELINE, t.risk_multiplier
    assert_equal 0, t.override_count
    assert_no_difference -> { ShopThreshold.count } do
      assert_equal t.id, ShopThreshold.for(SHOP).id
    end
  end

  test "record_override! raises sensitivity threshold and counts it" do
    t = ShopThreshold.for(SHOP)
    returned = t.record_override!
    assert_in_delta ShopThreshold::BASELINE + ShopThreshold::OVERRIDE_STEP, t.risk_multiplier, 0.001
    assert_equal t.risk_multiplier, returned
    assert_equal 1, t.override_count
    assert_predicate t, :persisted?
    assert_not t.changed?, "should be saved"
  end

  test "record_accept! lowers threshold back toward baseline" do
    t = ShopThreshold.for(SHOP)
    t.update!(risk_multiplier: 2.0)
    t.record_accept!
    assert_in_delta 2.0 - ShopThreshold::ACCEPT_STEP, t.risk_multiplier, 0.001
    assert_equal 1, t.accept_count
  end

  test "override is clamped at the ceiling" do
    t = ShopThreshold.for(SHOP)
    t.update!(risk_multiplier: ShopThreshold::CEILING)
    t.record_override!
    assert_equal ShopThreshold::CEILING, t.risk_multiplier
  end

  test "accept is clamped at the floor" do
    t = ShopThreshold.for(SHOP)
    t.update!(risk_multiplier: ShopThreshold::FLOOR)
    t.record_accept!
    assert_equal ShopThreshold::FLOOR, t.risk_multiplier
  end
end
