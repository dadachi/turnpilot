# Builds a situational snapshot for a flagged order, asks local Gemma for an advisory,
# persists it, and broadcasts it to the console via Turbo Streams.
class AdvisoryGenerator
  def self.for(order, now: Time.current, customer_waiting: false) = new(order, now:, customer_waiting:).call

  def initialize(order, now: Time.current, customer_waiting: false)
    @order = order
    @now = now
    @customer_waiting = customer_waiting # camera perception: is a customer visibly at the counter?
  end

  def call
    return nil if @order.suppressed? # staff overrode a similar advisory recently — stay quiet
    # A little more warmth than the default so rationales read naturally and vary between
    # orders instead of collapsing to one template; still low enough for reliable JSON.
    result = GemmaClient.advise(prompt(build_snapshot), temperature: 0.5)
    return nil unless Advisory.advise?(result["advise"]) # Gemma decided it's not worth interrupting staff
    advisory = @order.advisories.create!(
      kind: "walk_away_risk",
      status: :pending,
      shop_id: @order.shop_id,
      text: result["text"].to_s,
      rationale: result["rationale"].to_s,
      suggested_action: result["suggested_action"].to_s
    )
    broadcast(advisory)
    advisory
  rescue GemmaClient::Error => e
    Rails.logger.warn("[AdvisoryGenerator] #{e.message}")
    nil
  end

  private

  def build_snapshot
    baseline_min = (Order.baseline_cook_seconds(@order.shop_id) / 60.0).round(1)
    cooking_min = @order.cook_minutes(@now)
    {
      shop: "Cafe demo",
      baseline_cook_min: baseline_min,
      cooking_now: Order.live(@now).count,
      customer_waiting: @customer_waiting, # from the on-device camera (coarse); false if camera off/stale
      slow_order: {
        queue_number: @order.queue_number,
        cooking_min: cooking_min,
        # A distinct per-order anchor so Gemma can speak to THIS order's specific stakes.
        minutes_over_normal: (cooking_min - baseline_min).round(1)
      }
    }
  end

  def prompt(snapshot)
    <<~PROMPT
      You are TurnPilot, a live queue-ops copilot for a walk-in shop. An order has been
      cooking longer than this shop's normal, so the waiting customer may walk away. If
      `customer_waiting` is true, the counter camera sees a customer at the counter right now
      — weigh that as extra urgency.

      Reply with ONLY a JSON object (no prose, no markdown) with these keys:
        "advise": a JSON boolean — exactly true or false, never a word or label. true if
                  staff should act now; false if the delay is minor or nothing would help.
        "text": one short imperative sentence to staff.
        "rationale": one short sentence in a manager's voice on why THIS order matters right
                     now. Lead with a concrete, order-specific fact and VARY the opening and
                     angle every time — sometimes the minutes past normal, sometimes that the
                     customer is still at the counter, sometimes the knock-on to the rest of
                     the queue. Never reuse a stock opener (e.g. "This customer has waited
                     longer than usual" or "The slow order"), and don't just restate the raw
                     numbers already on screen.
        "suggested_action": a short snake_case action, e.g. check_kitchen or update_customer.

      Situation:
      #{JSON.pretty_generate(snapshot)}
    PROMPT
  end

  def broadcast(advisory)
    Turbo::StreamsChannel.broadcast_prepend_to(
      "console", target: "advisories",
      partial: "advisories/advisory", locals: { advisory: advisory }
    )
  end
end
