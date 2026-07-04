require "test_helper"

class AdvisoryTest < ActiveSupport::TestCase
  SHOP = "8f4c2b10-0000-4000-8000-000000000001".freeze

  test "a shop-level advisory is valid without an order" do
    advisory = Advisory.new(kind: "open_server", status: :pending, shop_id: SHOP,
                            text: "Open a second prep station.")
    assert advisory.valid?, advisory.errors.full_messages.to_sentence
    assert_nil advisory.order
  end

  test "an order-scoped advisory still works" do
    order = Order.create!(status: :prepared, shop_id: SHOP, prepared_at: Time.current)
    advisory = order.advisories.create!(kind: "walk_away_risk", status: :pending, shop_id: SHOP, text: "x")
    assert_equal order, advisory.order
  end
end
