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

  # Advance the clock, then generate advisories for the most-at-risk flagged orders that
  # lack a pending one. Flagging uses each shop's LEARNED threshold (raised by staff
  # Overrides), memoized per shop so we hit ShopThreshold once per shop, not once per order.
  def self.tick(limit: 3, now: Time.current)
    advance(now)
    threshold = Hash.new { |h, sid| h[sid] = ShopThreshold.for(sid).risk_multiplier }
    Order.live(now)
         .select { |o| o.flagged?(now, threshold: threshold[o.shop_id]) }
         .sort_by { |o| -o.walk_away_risk(now, threshold: threshold[o.shop_id]) }
         .reject { |o| o.advisories.pending.exists? || o.suppressed? }
         .first(limit)
         .filter_map { |o| AdvisoryGenerator.for(o, now: now) }
  end
end
