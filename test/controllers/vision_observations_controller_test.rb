require "test_helper"

class VisionObservationsControllerTest < ActionDispatch::IntegrationTest
  SHOP = "8f4c2b10-0000-4000-8000-000000000001".freeze
  READ = { "people_present" => true, "queue_level" => "busy", "note" => "a line at the counter" }.freeze

  def stubbing(receiver, name, impl)
    original = receiver.singleton_method(name)
    receiver.define_singleton_method(name, impl)
    yield
  ensure
    receiver.define_singleton_method(name, original)
  end

  setup do
    # An order so the controller can resolve the demo shop_id.
    Order.create!(status: :prepared, shop_id: SHOP, prepared_at: Time.current)
  end

  test "create persists only the coarse signal and strips the data-URI before vision" do
    seen = nil
    stubbing(VisionClient, :observe, ->(frame) { seen = frame; READ }) do
      assert_difference -> { VisionObservation.count }, 1 do
        post vision_observations_path, params: { frame: "data:image/jpeg;base64,QUJD" }
      end
    end
    assert_response :ok
    assert_equal "QUJD", seen, "data-URI prefix must be stripped before the vision call"

    o = VisionObservation.last
    assert_equal SHOP, o.shop_id
    assert_equal true, o.people_present
    assert_equal "busy", o.queue_level
    assert_equal "a line at the counter", o.note
    # The model has no column that could hold a frame — privacy by construction.
    assert_not o.attributes.keys.any? { |k| k.match?(/frame|image|photo|blob/) }
  end

  test "create is inert (no observation) when vision returns nil" do
    stubbing(VisionClient, :observe, ->(*) { nil }) do
      assert_no_difference -> { VisionObservation.count } do
        post vision_observations_path, params: { frame: "data:image/jpeg;base64,QUJD" }
      end
    end
    assert_response :ok
  end

  test ":frame is filtered from logs" do
    # Assert the behavior (a frame param is redacted), robust to whether filter_parameters is
    # a symbol list (dev) or a compiled regexp (eager-loaded CI).
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
                                             .filter("frame" => "base64-secret")
    assert_equal "[FILTERED]", filtered["frame"]
  end

  test "simulate seeds a camera scenario and redirects to the console" do
    assert_difference -> { VisionObservation.count }, 3 do
      post vision_simulate_path(scenario: "left")
    end
    assert_redirected_to console_path
  end
end
