# A coarse, ephemeral read of the shop's counter from the camera (via local Gemma vision).
# Stores ONLY the derived signal — never a frame (the table has no blob column by design).
# Feeds the situational model as the "is a customer present / queue pressure" signal that
# MyTurnTag's event data cannot provide. See docs/vision-capstone-spec.md.
class VisionObservation < ApplicationRecord
  # Coarse pressure band — never a count. Prefixed because "none" collides with
  # ActiveRecord's built-in `.none` (predicates become queue_level_none? etc).
  enum :queue_level, { none: 0, light: 1, busy: 2 }, prefix: true

  FRESH_WINDOW = 30.seconds # older than this = stale → treated as "no perception"
  RETENTION    = 1.hour     # working state only; pruned aggressively

  scope :for_shop, ->(shop_id) { where(shop_id: shop_id) }

  # The most recent observation for a shop as of `now` (nil if none).
  def self.latest_for(shop_id, now = Time.current)
    for_shop(shop_id).where(observed_at: ..now).order(observed_at: :desc).first
  end

  # Recorded recently enough to trust. Stale/absent perception must never create urgency.
  def fresh?(now = Time.current, window: FRESH_WINDOW)
    observed_at.present? && observed_at >= now - window
  end

  # Ephemeral working state — drop anything older than the retention window.
  def self.prune!(now = Time.current)
    where(observed_at: ...(now - RETENTION)).delete_all
  end
end
