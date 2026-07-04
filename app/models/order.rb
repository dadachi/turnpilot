class Order < ApplicationRecord
  has_many :advisories, dependent: :destroy

  enum :status, { waiting: 0, prepared: 1, completed: 2 }

  # v1: a per-shop baseline constant (later: from MyTurnTag stats_averages).
  BASELINE_PREP_SECONDS = 6 * 60
  RISK_THRESHOLD = 1.5   # flag when wait exceeds baseline * threshold

  scope :open, -> { where.not(status: :completed) }

  # How long this order has been waiting for prep (frozen once prepared).
  def wait_seconds(now = Time.current)
    return 0 if completed_at
    ((prepared_at || now) - joined_at).to_i
  end

  # 0.0..; >= 1.0 means past the flag threshold.
  def walk_away_risk(now = Time.current)
    return 0.0 unless waiting?
    (wait_seconds(now).to_f / (BASELINE_PREP_SECONDS * RISK_THRESHOLD)).round(2)
  end

  def flagged?(now = Time.current)
    waiting? && wait_seconds(now) > BASELINE_PREP_SECONDS * RISK_THRESHOLD
  end

  def wait_minutes(now = Time.current) = (wait_seconds(now) / 60.0).round(1)
end
