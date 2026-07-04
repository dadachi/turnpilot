# Replays the synthetic queue event stream (db/fixtures/synthetic_rush.json) into Order
# records. For a reproducible demo it anchors the stream so "now" sits mid-rush, leaving
# several orders waiting past the walk-away threshold. `tick` then fires advisories for
# flagged orders that don't have a fresh one yet.
class Replayer
  FIXTURE = Rails.root.join("db/fixtures/synthetic_rush.json")

  # Seed Orders from the stream. `anchor_minutes_ago` places the busiest part of the rush
  # relative to Time.current so the demo has live, flagged orders on load.
  def self.seed(anchor_minutes_ago: 12)
    events = JSON.parse(File.read(FIXTURE))
    base = Time.parse(events.first["at"])
    shift = Time.current - base - anchor_minutes_ago.minutes

    Order.delete_all
    by_qn = {}
    events.each do |e|
      at = Time.parse(e["at"]) + shift
      order = by_qn[e["queue_number"]] ||= Order.new(
        shop_id: e["shop_id"], queue_number: e["queue_number"], status: :waiting
      )
      case e["event"]
      when "joined"        then order.joined_at = at
      when "prepared"      then order.assign_attributes(prepared_at: at, status: :prepared)
      when "customer_read" then order.customer_read_at = at
      when "completed"     then order.assign_attributes(completed_at: at, status: :completed)
      end
    end
    # keep only events up to "now"; drop future joins
    by_qn.values.select { |o| o.joined_at && o.joined_at <= Time.current }.each(&:save!)
    Order.count
  end

  # Generate advisories for the most-at-risk flagged orders lacking a pending one.
  # Flagging uses each shop's LEARNED threshold (raised by staff Overrides), memoized
  # per shop so we hit ShopThreshold once per shop, not once per order.
  def self.tick(limit: 3)
    threshold = Hash.new { |h, sid| h[sid] = ShopThreshold.for(sid).risk_multiplier }
    Order.open
         .select { |o| o.flagged?(threshold: threshold[o.shop_id]) }
         .sort_by { |o| -o.walk_away_risk(threshold: threshold[o.shop_id]) }
         .reject { |o| o.advisories.pending.exists? }
         .first(limit)
         .filter_map { |o| AdvisoryGenerator.for(o) }
  end
end
