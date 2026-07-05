# Shop-level advisory: the counter camera saw a customer, then they're gone — while an order
# is STILL cooking past this shop's normal. The waiting customer may have just walked away →
# check / re-notify. A single frame can't answer "did someone leave?", so it's derived by
# DEBOUNCED change detection: the two most-recent observations are both absent (confirms it
# isn't a one-frame flicker) following a present one. Order-less, like OpenServerAdvisor.
class WalkedAwayAdvisor
  def self.for(shop_id, now: Time.current) = new(shop_id, now:).call

  def initialize(shop_id, now: Time.current)
    @shop_id = shop_id
    @now = now
  end

  def call
    return nil unless someone_left? && flagged_order_cooking?
    return nil if recently_advised?

    result = GemmaClient.advise(prompt(snapshot))
    return nil unless Advisory.advise?(result["advise"])

    advisory = Advisory.create!(
      kind: "walked_away", status: :pending, shop_id: @shop_id,
      text: result["text"].to_s, rationale: result["rationale"].to_s,
      suggested_action: result["suggested_action"].to_s
    )
    broadcast(advisory)
    advisory
  rescue GemmaClient::Error => e
    Rails.logger.warn("[WalkedAwayAdvisor] #{e.message}")
    nil
  end

  private

  # Present -> absent -> absent across the three most-recent observations (debounced).
  def someone_left?
    recent = VisionObservation.for_shop(@shop_id)
                              .where(observed_at: (@now - 2.minutes)..@now)
                              .order(observed_at: :desc).limit(3).to_a
    return false unless recent.size >= 3 && recent.first.fresh?(@now)

    !recent[0].people_present && !recent[1].people_present && recent[2].people_present
  end

  # There's a genuinely at-risk order still cooking — otherwise a customer leaving is just a
  # normal handoff, not a walk-away.
  def flagged_order_cooking?
    t = ShopThreshold.for(@shop_id).risk_multiplier
    b = Order.baseline_cook_seconds(@shop_id)
    Order.live(@now).where(shop_id: @shop_id).any? { |o| o.flagged?(@now, threshold: t, baseline: b) }
  end

  def recently_advised?
    Advisory.where(shop_id: @shop_id, kind: "walked_away")
            .where(created_at: Advisory::SUPPRESSION_WINDOW.ago..).exists?
  end

  def snapshot
    { shop: "Cafe demo", cooking_now: Order.cooking_count(@shop_id, @now),
      camera: "a waiting customer was visible and is now gone" }
  end

  def prompt(snapshot)
    <<~PROMPT
      You are TurnPilot, a live queue-ops copilot for a walk-in shop. The counter camera saw a
      customer waiting and now they're gone, while an order is still cooking past normal — the
      customer may have just walked away.

      Reply with ONLY a JSON object (no prose):
        "advise": JSON boolean — true if staff should act (re-notify / check on the order) now.
        "text": one short imperative sentence to staff.
        "rationale": brief reason (cite the customer leaving + the slow order).
        "suggested_action": short snake_case action, e.g. re_notify_customer.

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
