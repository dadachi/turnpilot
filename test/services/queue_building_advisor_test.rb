require "test_helper"

class QueueBuildingAdvisorTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 7, 5, 12, 0, 0)
  SHOP = "8f4c2b10-0000-4000-8000-000000000001".freeze
  ADVICE = { "advise" => true, "text" => "Start taking orders.", "rationale" => "line forming", "suggested_action" => "start_taking_orders" }.freeze

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

  def busy_camera(at: NOW)
    VisionObservation.create!(shop_id: SHOP, observed_at: at, queue_level: :busy, people_present: true)
  end

  test "advises when the camera is busy and nothing is cooking" do
    busy_camera
    with_gemma(ADVICE) do
      advisory = nil
      assert_difference -> { Advisory.count }, 1 do
        advisory = QueueBuildingAdvisor.for(SHOP, now: NOW)
      end
      assert_equal "queue_building", advisory.kind
      assert_nil advisory.order, "shop-level advisory has no order"
      assert_equal SHOP, advisory.shop_id
    end
  end

  test "stays quiet when something is already cooking" do
    busy_camera
    Order.create!(status: :prepared, shop_id: SHOP, prepared_at: NOW - 60)
    with_gemma(ADVICE) { assert_nil QueueBuildingAdvisor.for(SHOP, now: NOW) }
  end

  test "stays quiet when the camera is not busy" do
    VisionObservation.create!(shop_id: SHOP, observed_at: NOW, queue_level: :light, people_present: true)
    with_gemma(ADVICE) { assert_nil QueueBuildingAdvisor.for(SHOP, now: NOW) }
  end

  test "stays quiet with only a stale observation" do
    busy_camera(at: NOW - (VisionObservation::FRESH_WINDOW + 1.minute))
    with_gemma(ADVICE) { assert_nil QueueBuildingAdvisor.for(SHOP, now: NOW) }
  end

  test "suppresses a repeat within the window" do
    busy_camera
    with_gemma(ADVICE) do
      assert_not_nil QueueBuildingAdvisor.for(SHOP, now: NOW)
      assert_no_difference -> { Advisory.count } do
        assert_nil QueueBuildingAdvisor.for(SHOP, now: NOW)
      end
    end
  end

  test "respects a Gemma advise:false veto" do
    busy_camera
    with_gemma(ADVICE.merge("advise" => false)) { assert_nil QueueBuildingAdvisor.for(SHOP, now: NOW) }
  end
end
