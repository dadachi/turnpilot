require "test_helper"

class AdvisoriesControllerTest < ActionDispatch::IntegrationTest
  SHOP = "8f4c2b10-0000-4000-8000-000000000001".freeze

  setup do
    @order = Order.create!(status: :waiting, shop_id: SHOP, queue_number: "7",
                           joined_at: 11.minutes.ago)
    @advisory = @order.advisories.create!(kind: "walk_away_risk", status: :pending, shop_id: SHOP,
                                          text: "Call queue #7.", rationale: "Waited long.")
  end

  test "accept marks the advisory accepted and nudges the threshold down" do
    ShopThreshold.for(SHOP).update!(risk_multiplier: 2.0)

    patch accept_advisory_path(@advisory)

    assert_response :ok
    assert @advisory.reload.accepted?
    assert_in_delta 2.0 - ShopThreshold::ACCEPT_STEP, ShopThreshold.for(SHOP).risk_multiplier, 0.001
    assert_equal 1, ShopThreshold.for(SHOP).accept_count
  end

  test "override marks the advisory overridden and raises the threshold" do
    baseline = ShopThreshold.for(SHOP).risk_multiplier

    patch override_advisory_path(@advisory)

    assert_response :ok
    assert @advisory.reload.overridden?
    assert_in_delta baseline + ShopThreshold::OVERRIDE_STEP, ShopThreshold.for(SHOP).risk_multiplier, 0.001
    assert_equal 1, ShopThreshold.for(SHOP).override_count
  end

  test "override works on a shop-level advisory with no order" do
    shop_advisory = Advisory.create!(kind: "open_server", status: :pending, shop_id: SHOP,
                                     text: "Open a prep station.")
    baseline = ShopThreshold.for(SHOP).risk_multiplier

    patch override_advisory_path(shop_advisory)

    assert_response :ok
    assert shop_advisory.reload.overridden?
    assert_in_delta baseline + ShopThreshold::OVERRIDE_STEP, ShopThreshold.for(SHOP).risk_multiplier, 0.001
  end
end
