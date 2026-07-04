class Order < ApplicationRecord
  has_many :advisories, dependent: :destroy

  # Mirrors MyTurnTag's ItemTag lifecycle (preparing_mode): waiting≈idled → prepared
  # (cooking STARTED) → completed (cooking finished). Only prepared_at/completed_at are
  # reliable (staff actions); there is no recorded customer-join, so we never model one.
  enum :status, { waiting: 0, prepared: 1, completed: 2 }

  # Baseline cook time (prepared→completed). v1 constant; a per-shop learned average
  # (avg of completed cook durations) can override it via the `baseline:` argument.
  BASELINE_COOK_SECONDS = 6 * 60
  RISK_THRESHOLD = 1.5   # default multiplier; a shop's learned value (ShopThreshold) overrides

  scope :open, -> { where.not(status: :completed) }
  scope :joined_by, ->(t = Time.current) { where(joined_at: ..t) }
  scope :not_completed_by, ->(t = Time.current) { where("completed_at IS NULL OR completed_at > ?", t) }
  # Timeline-driven "currently in the queue" as of t: appeared and not yet completed.
  scope :live, ->(t = Time.current) { joined_by(t).not_completed_by(t) }

  # Seconds the order has been cooking: prepared→completed, or prepared→now while still
  # cooking. 0 before cooking starts (no honest wait signal exists pre-`prepared`).
  def cook_seconds(now = Time.current)
    return 0 unless prepared_at && prepared_at <= now

    # Freeze at completion once cooked; otherwise count up to now. (completed_at may be a
    # future scripted time during replay, so `|| now` isn't enough — cap it at now.)
    finish = completed_at && completed_at <= now ? completed_at : now
    (finish - prepared_at).to_i
  end

  # Actively cooking = preparation started and not yet completed, as of `now`.
  def cooking?(now = Time.current)
    prepared_at.present? && prepared_at <= now && (completed_at.nil? || completed_at > now)
  end

  # 0.0..; >= 1.0 means past the flag threshold. `threshold` is the shop's learned
  # sensitivity multiplier; `baseline` is the shop's normal cook time in seconds.
  def walk_away_risk(now = Time.current, threshold: RISK_THRESHOLD, baseline: BASELINE_COOK_SECONDS)
    return 0.0 unless cooking?(now)

    (cook_seconds(now).to_f / (baseline * threshold)).round(2)
  end

  # A currently-cooking order whose cook time has run past the shop's normal → the
  # customer is waiting on a slow order and may walk away.
  def flagged?(now = Time.current, threshold: RISK_THRESHOLD, baseline: BASELINE_COOK_SECONDS)
    cooking?(now) && cook_seconds(now) > baseline * threshold
  end

  def cook_minutes(now = Time.current) = (cook_seconds(now) / 60.0).round(1)

  # Honest ETA = seconds remaining until this order reaches the shop's normal cook time.
  # 0 once it's overdue (already past normal); nil when not cooking. There is no pre-cook
  # ETA in the real model (no join), so ETA only exists for in-progress orders.
  def eta_seconds(now = Time.current, baseline: BASELINE_COOK_SECONDS)
    return nil unless cooking?(now)

    [ baseline - cook_seconds(now), 0 ].max
  end

  def eta_minutes(now = Time.current, baseline: BASELINE_COOK_SECONDS)
    secs = eta_seconds(now, baseline: baseline)
    secs && (secs / 60.0).round(1)
  end

  # This shop's *normal* cook time, learned from history: the average prepared→completed
  # duration over recent completed orders. Falls back to the constant until there's enough
  # signal. This is what "vs this shop's normal" honestly means (both timestamps are
  # staff-recorded), replacing a hardcoded baseline.
  def self.baseline_cook_seconds(shop_id, sample: 20, min_samples: 3)
    durations = completed.where(shop_id: shop_id).where.not(prepared_at: nil)
                         .order(completed_at: :desc).limit(sample)
                         .pluck(:prepared_at, :completed_at)
                         .filter_map { |prep, done| (done - prep).to_i if done && prep && done > prep }
    return BASELINE_COOK_SECONDS if durations.size < min_samples

    (durations.sum.to_f / durations.size).round
  end

  # --- shop-level throughput signals (feed the open-a-server advisory) -----
  # Both derive only from recorded staff timestamps (prepared/completed), so they stay
  # honest under the real MyTurnTag model.

  # Orders actively cooking (prepared, not yet completed) for a shop at `now` — the backlog.
  # Defined purely by the cook timestamps, independent of when the tag was created.
  scope :cooking_at, ->(t = Time.current) { where(prepared_at: ..t).not_completed_by(t) }

  def self.cooking_count(shop_id, now = Time.current)
    cooking_at(now).where(shop_id: shop_id).count
  end

  # Completions in the trailing `window` — the rolling throughput numerator.
  def self.completions_in(shop_id, window, now = Time.current)
    where(shop_id: shop_id).where(completed_at: (now - window)..now).count
  end

  # True when a same-kind advisory was overridden within the suppression window — staff
  # just rejected this; don't re-advise until it lapses.
  def suppressed?(kind: "walk_away_risk", window: Advisory::SUPPRESSION_WINDOW)
    advisories.overridden.where(kind: kind).where(created_at: window.ago..).exists?
  end

  # The status implied by this order's event timeline at time `now`. The stored
  # timestamps are the replay "script"; the Replayer materializes status from them as
  # the clock advances.
  def materialized_status(now = Time.current)
    return :completed if completed_at && completed_at <= now
    return :prepared if prepared_at && prepared_at <= now

    :waiting
  end

  # Advance this order's stored status to match its timeline at `now`.
  def materialize!(now = Time.current)
    want = materialized_status(now)
    update!(status: want) unless status == want.to_s
    self
  end
end
