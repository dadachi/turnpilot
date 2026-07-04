class Order < ApplicationRecord
  has_many :advisories, dependent: :destroy

  enum :status, { waiting: 0, prepared: 1, completed: 2 }

  # v1: a per-shop baseline constant (later: from MyTurnTag stats_averages).
  BASELINE_PREP_SECONDS = 6 * 60
  RISK_THRESHOLD = 1.5   # default multiplier; a shop's learned value (ShopThreshold) overrides

  scope :open, -> { where.not(status: :completed) }

  # How long this order has been waiting for prep (frozen once prepared).
  def wait_seconds(now = Time.current)
    return 0 if completed_at
    ((prepared_at || now) - joined_at).to_i
  end

  # 0.0..; >= 1.0 means past the flag threshold. `threshold` is the shop's learned
  # sensitivity multiplier (defaults to the baseline constant).
  def walk_away_risk(now = Time.current, threshold: RISK_THRESHOLD)
    return 0.0 unless waiting?
    (wait_seconds(now).to_f / (BASELINE_PREP_SECONDS * threshold)).round(2)
  end

  def flagged?(now = Time.current, threshold: RISK_THRESHOLD)
    waiting? && wait_seconds(now) > BASELINE_PREP_SECONDS * threshold
  end

  def wait_minutes(now = Time.current) = (wait_seconds(now) / 60.0).round(1)

  # True when a same-kind advisory was overridden within the suppression window — staff
  # just rejected this; don't re-advise until it lapses.
  def suppressed?(kind: "walk_away_risk", window: Advisory::SUPPRESSION_WINDOW)
    advisories.overridden.where(kind: kind).where(created_at: window.ago..).exists?
  end
end
