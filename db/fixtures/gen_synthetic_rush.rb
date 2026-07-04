# Regenerates db/fixtures/synthetic_rush.json — the deterministic demo rush.
#
#   mise exec -- ruby db/fixtures/gen_synthetic_rush.rb
#
# Times are relative to a base T0 that Replayer.seed maps to (now - anchor). With the
# default 12-min anchor, "now" sits at T0+12, so orders prepared near T0 that finish after
# T0+12 are still cooking past the 9-min flag window (baseline 6 min × 1.5).
require "json"
require "time"

SHOP = "8f4c2b10-0000-4000-8000-000000000001".freeze
T0 = Time.utc(2026, 7, 4, 11, 31, 0)

# [queue, joined(min), prepared(min), completed(min or nil)] relative to T0.
ORDERS = [
  # slow cooks — still cooking at the anchor, past the window → FLAGGED
  [ "1", 0.0, 0.5, 14.0 ],
  [ "2", 1.0, 1.5, 15.0 ],
  [ "3", 2.0, 2.5, 16.0 ],
  # normal quick cooks — completed before the anchor (history)
  [ "4", 0.5, 1.0, 6.0 ],
  [ "5", 2.0, 3.0, 8.0 ],
  [ "6", 3.0, 4.0, 9.5 ],
  [ "7", 4.0, 5.0, 10.5 ],
  # recently started — cooking but under the window at the anchor
  [ "8", 8.0, 9.0, 15.0 ],
  [ "9", 9.5, 10.5, 16.0 ],
  # future — revealed as the ticking replayer advances past the anchor
  [ "10", 12.5, 13.5, 18.0 ],
  [ "11", 13.0, 14.5, 19.0 ],
  [ "12", 14.0, 15.5, 20.0 ]
].freeze

at = ->(min) { (T0 + (min * 60).round).iso8601 }
events = []
ORDERS.each do |qn, j, p, c|
  events << { shop_id: SHOP, queue_number: qn, event: "joined",    at: at.call(j), actor: "customer" }
  events << { shop_id: SHOP, queue_number: qn, event: "prepared",  at: at.call(p), actor: "staff" }
  events << { shop_id: SHOP, queue_number: qn, event: "completed", at: at.call(c), actor: "staff" } if c
end
events.sort_by! { |e| Time.parse(e[:at]) }

path = File.expand_path("synthetic_rush.json", __dir__)
File.write(path, JSON.pretty_generate(events) + "\n")
puts "wrote #{events.size} events to #{path}"
