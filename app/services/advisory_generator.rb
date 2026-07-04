# Builds a situational snapshot for a flagged order, asks local Gemma for an advisory,
# persists it, and broadcasts it to the console via Turbo Streams.
class AdvisoryGenerator
  def self.for(order, now: Time.current) = new(order, now:).call

  def initialize(order, now: Time.current)
    @order = order
    @now = now
  end

  def call
    return nil if @order.suppressed? # staff overrode a similar advisory recently — stay quiet
    result = GemmaClient.advise(prompt(build_snapshot))
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
    {
      shop: "Cafe demo",
      baseline_cook_min: (Order.baseline_cook_seconds(@order.shop_id) / 60.0).round(1),
      cooking_now: Order.live(@now).count,
      slow_order: {
        queue_number: @order.queue_number,
        cooking_min: @order.cook_minutes(@now)
      }
    }
  end

  def prompt(snapshot)
    <<~PROMPT
      You are TurnPilot, a live queue-ops copilot for a walk-in shop. An order has been
      cooking longer than this shop's normal, so the waiting customer may walk away.

      Reply with ONLY a JSON object (no prose, no markdown) with these keys:
        "advise": a JSON boolean — exactly true or false, never a word or label. true if
                  staff should act now; false if the delay is minor or nothing would help.
        "text": one short imperative sentence to staff.
        "rationale": brief reason (cite the cook time vs the shop's normal).
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
