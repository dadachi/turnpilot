require "test_helper"

class VisionObservationTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 7, 5, 12, 0, 0)
  SHOP = "8f4c2b10-0000-4000-8000-000000000001".freeze
  OTHER = "8f4c2b10-0000-4000-8000-000000000002".freeze

  def obs(shop: SHOP, at: NOW, level: :light, present: true)
    VisionObservation.create!(shop_id: shop, observed_at: at, queue_level: level, people_present: present)
  end

  test "queue_level is a coarse three-band enum" do
    assert_equal %w[none light busy], VisionObservation.queue_levels.keys
  end

  test "latest_for returns the most recent observation for the shop, as of now" do
    obs(at: NOW - 60)
    newest = obs(at: NOW - 10)
    obs(at: NOW + 30) # in the future relative to NOW — excluded
    obs(shop: OTHER, at: NOW - 5) # other shop — excluded
    assert_equal newest.id, VisionObservation.latest_for(SHOP, NOW).id
  end

  test "fresh? is true only within the freshness window" do
    assert obs(at: NOW - 10).fresh?(NOW)
    assert_not obs(at: NOW - (VisionObservation::FRESH_WINDOW + 5.seconds)).fresh?(NOW)
  end

  test "prune! drops observations older than the retention window" do
    obs(at: NOW - 5.minutes)                                   # kept
    obs(at: NOW - (VisionObservation::RETENTION + 10.minutes)) # pruned
    assert_difference -> { VisionObservation.count }, -1 do
      VisionObservation.prune!(NOW)
    end
  end
end
