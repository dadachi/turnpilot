# Replays the synthetic queue event stream (db/fixtures/synthetic_rush.json) into Order
# records. Each order stores its full (time-shifted) event timeline; `advance` materializes
# status from that timeline as the clock moves, so the rush plays out live. `seed` anchors
# the stream so "now" sits mid-rush (several orders already past the walk-away threshold),
# and `tick` fires advisories for the most-at-risk flagged orders.
class Replayer
  FIXTURE = Rails.root.join("db/fixtures/synthetic_rush.json")

  # Load every order's full timeline from the stream. `anchor_minutes_ago` places the
  # busiest part of the rush relative to `now` so the demo opens with live, flagged orders.
  # Future joins are stored too (hidden by the `live` scope) so `advance` can reveal them.
  def self.seed(anchor_minutes_ago: 12, now: Time.current)
    events = JSON.parse(File.read(FIXTURE))
    base = Time.parse(events.first["at"])
    shift = now - base - anchor_minutes_ago.minutes

    Advisory.delete_all # advisories FK-reference orders; clear them before resetting orders
    Order.delete_all
    ShopThreshold.delete_all # fresh demo: reset each shop's learned sensitivity to baseline
    by_qn = {}
    events.each do |e|
      at = Time.parse(e["at"]) + shift
      order = by_qn[e["queue_number"]] ||= Order.new(
        shop_id: e["shop_id"], queue_number: e["queue_number"], status: :waiting
      )
      case e["event"]
      when "joined"        then order.joined_at = at
      when "prepared"      then order.prepared_at = at
      when "customer_read" then order.customer_read_at = at
      when "completed"     then order.completed_at = at
      end
    end
    by_qn.values.select(&:joined_at).each do |o|
      o.status = o.materialized_status(now)
      o.save!
    end
    Order.live(now).count
  end

  # Move the simulation clock to `now`: re-derive each order's status from its stored
  # timeline (reveal joins, mark prepared/completed as their times pass). Idempotent.
  def self.advance(now = Time.current)
    Order.find_each { |o| o.materialize!(now) }
    Order.live(now).count
  end

  TICK_LOCK_KEY = 4271 # arbitrary constant key for the advisory lock below

  # Advance the clock, then generate advisories for the most-at-risk flagged orders that
  # lack a pending one. Flagging uses each shop's LEARNED threshold (raised by staff
  # Overrides), memoized per shop so we hit ShopThreshold once per shop, not once per order.
  #
  # Serialized with a Postgres advisory lock: a tick makes several slow Gemma calls, and the
  # live poller (plus the Run-rush tick) can overlap. Concurrent ticks would race the
  # "already has a pending advisory?" / suppression checks and create duplicates, so an
  # overlapping tick simply no-ops instead.
  def self.tick(limit: 3, now: Time.current)
    conn = ActiveRecord::Base.connection
    return [] if conn.select_value("SELECT pg_try_advisory_lock(#{TICK_LOCK_KEY})::int").to_i.zero?

    begin
      advance(now)
      walk_away(now, limit) + open_server(now) + queue_building(now) + walked_away(now)
    ensure
      conn.execute("SELECT pg_advisory_unlock(#{TICK_LOCK_KEY})")
    end
  end

  ESCALATION_RISK = 0.8 # a borderline cook advises early when the camera sees a waiting customer

  # Per-order walk-away-risk advisories for the most-at-risk flagged orders. Flagging uses
  # each shop's LEARNED threshold and baseline (memoized per shop). Camera perception lets a
  # BORDERLINE cook (>= ESCALATION_RISK, not yet flagged) advise when a customer is visibly
  # waiting — filling the "is anyone actually waiting?" gap MyTurnTag's data can't answer.
  def self.walk_away(now, limit)
    threshold = Hash.new { |h, sid| h[sid] = ShopThreshold.for(sid).risk_multiplier }
    baseline  = Hash.new { |h, sid| h[sid] = Order.baseline_cook_seconds(sid) }
    waiting   = Hash.new { |h, sid| h[sid] = customer_waiting?(sid, now) }

    Order.live(now)
         .select do |o|
           t = threshold[o.shop_id]
           b = baseline[o.shop_id]
           o.flagged?(now, threshold: t, baseline: b) ||
             (waiting[o.shop_id] && o.walk_away_risk(now, threshold: t, baseline: b) >= ESCALATION_RISK)
         end
         .sort_by { |o| -o.walk_away_risk(now, threshold: threshold[o.shop_id], baseline: baseline[o.shop_id]) }
         .reject { |o| o.advisories.pending.exists? || o.suppressed? }
         .first(limit)
         .filter_map { |o| AdvisoryGenerator.for(o, now: now, customer_waiting: waiting[o.shop_id]) }
  end

  # Shop-level "customers are lining up but nothing has been started" nudge — per shop with a
  # fresh camera observation.
  def self.queue_building(now)
    camera_shops(now).filter_map { |sid| QueueBuildingAdvisor.for(sid, now: now) }
  end

  # Shop-level "a waiting customer just left while an order is still cooking" advisories.
  def self.walked_away(now)
    camera_shops(now).filter_map { |sid| WalkedAwayAdvisor.for(sid, now: now) }
  end

  # Shops with a fresh camera observation.
  def self.camera_shops(now)
    VisionObservation.where(observed_at: (now - VisionObservation::FRESH_WINDOW)..now)
                     .distinct.pluck(:shop_id).compact
  end

  # Fresh "a customer is visibly waiting" signal for a shop (false when camera off/stale/empty).
  def self.customer_waiting?(shop_id, now)
    obs = VisionObservation.latest_for(shop_id, now)
    obs.present? && obs.fresh?(now) && obs.people_present
  end

  DEMO_SHOP_ID = "8f4c2b10-0000-4000-8000-000000000001" # the fixture shop (synthetic_rush.json)

  # Deterministic camera seeding for the demo — so each vision advisory reproduces on cue
  # WITHOUT a live camera or a live Gemma-vision read (the advisory itself still uses real
  # Gemma). Mirrors the deterministic replayer: fixed observations, reproducible beats.
  def self.simulate_vision(scenario, now: Time.current, shop_id: demo_shop_id)
    case scenario.to_s
    when "waiting" # a customer at the counter → escalates a borderline cook
      seed_observation(shop_id, now, present: true, level: :light)
    when "busy"    # a line forms → queue-building nudge (when nothing is cooking)
      seed_observation(shop_id, now, present: true, level: :busy)
    when "left"    # present → absent → absent → walk-away detection
      seed_observation(shop_id, now - 10, present: true,  level: :light)
      seed_observation(shop_id, now - 5,  present: false, level: :none)
      seed_observation(shop_id, now,      present: false, level: :none)
    end
    VisionObservation.latest_for(shop_id, now)
  end

  def self.seed_observation(shop_id, at, present:, level:)
    VisionObservation.create!(shop_id: shop_id, observed_at: at, people_present: present, queue_level: level)
  end

  # The shop the demo attributes camera observations to (the one with orders, else the fixture).
  def self.demo_shop_id
    Order.where.not(shop_id: nil).pick(:shop_id) || DEMO_SHOP_ID
  end

  # One shop-level open-a-server advisory per shop that's falling behind.
  def self.open_server(now)
    Order.live(now).distinct.pluck(:shop_id).compact
         .filter_map { |sid| OpenServerAdvisor.for(sid, now: now) }
  end
end
