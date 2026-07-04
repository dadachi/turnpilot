require "test_helper"

class ConsoleControllerTest < ActionDispatch::IntegrationTest
  test "index renders" do
    get console_path
    assert_response :ok
  end

  test "tick advances the sim and responds ok" do
    # No live flagged orders here, so Replayer.tick makes no Gemma call.
    assert_no_difference -> { Advisory.count } do
      post console_tick_path
    end
    assert_response :ok
  end
end
