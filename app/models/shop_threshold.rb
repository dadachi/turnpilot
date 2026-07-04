# Per-shop learned sensitivity for walk-away-risk advisories.
#
# Staff feedback tunes how eager TurnPilot is to advise: an Override (staff rejected the
# advisory) raises the multiplier so we advise LESS — stop advising what they reject — and
# an Accept nudges it back toward baseline. The multiplier scales the wait threshold in
# Order#flagged? / #walk_away_risk. Loose shop_id reference (no FK), per the MyTurnTag rules.
class ShopThreshold < ApplicationRecord
  BASELINE = Order::RISK_THRESHOLD  # starting multiplier (× baseline time-to-prepared)
  FLOOR    = 1.0                    # never advise before the baseline wait is reached
  CEILING  = 4.0                    # cap how insensitive staff feedback can push it
  OVERRIDE_STEP = 0.15              # become less sensitive when an advisory is rejected
  ACCEPT_STEP   = 0.10              # drift back toward baseline when one is accepted

  # The shop's current learned threshold, created at baseline on first use.
  def self.for(shop_id)
    find_or_create_by!(shop_id: shop_id) { |t| t.risk_multiplier = BASELINE }
  end

  # Read-only current multiplier (BASELINE if none learned yet). Safe to call from views —
  # unlike `.for`, it never creates a row.
  def self.multiplier_for(shop_id)
    find_by(shop_id: shop_id)&.risk_multiplier || BASELINE
  end

  def record_override! = adjust(OVERRIDE_STEP, :override_count)
  def record_accept!   = adjust(-ACCEPT_STEP, :accept_count)

  private

  def adjust(delta, counter)
    self.risk_multiplier = (risk_multiplier + delta).clamp(FLOOR, CEILING).round(2)
    self[counter] += 1
    save!
    risk_multiplier
  end
end
