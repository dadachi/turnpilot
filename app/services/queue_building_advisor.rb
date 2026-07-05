# Shop-level advisory: the counter camera sees customers lining up (queue_level "busy") while
# NOTHING is cooking — the kitchen may not have noticed the queue. Order-less, like
# OpenServerAdvisor: own suppression window + Gemma advise-veto. Inert unless there's a FRESH
# camera observation (camera off / stale / Ollama down → nothing fires). See the vision spec.
class QueueBuildingAdvisor
  def self.for(shop_id, now: Time.current) = new(shop_id, now:).call

  def initialize(shop_id, now: Time.current)
    @shop_id = shop_id
    @now = now
  end

  def call
    return nil unless building?
    return nil if recently_advised?

    result = GemmaClient.advise(prompt(snapshot))
    return nil unless Advisory.advise?(result["advise"])

    advisory = Advisory.create!(
      kind: "queue_building", status: :pending, shop_id: @shop_id,
      text: result["text"].to_s, rationale: result["rationale"].to_s,
      suggested_action: result["suggested_action"].to_s
    )
    broadcast(advisory)
    advisory
  rescue GemmaClient::Error => e
    Rails.logger.warn("[QueueBuildingAdvisor] #{e.message}")
    nil
  end

  private

  # Customers visibly lining up while the kitchen hasn't started anything.
  def building?
    obs.present? && obs.fresh?(@now) && obs.queue_level_busy? && Order.cooking_count(@shop_id, @now).zero?
  end

  def obs = @obs ||= VisionObservation.latest_for(@shop_id, @now)

  def recently_advised?
    Advisory.where(shop_id: @shop_id, kind: "queue_building")
            .where(created_at: Advisory::SUPPRESSION_WINDOW.ago..).exists?
  end

  def snapshot
    { shop: "Cafe demo", queue_level: "busy", cooking_now: Order.cooking_count(@shop_id, @now),
      camera_note: obs&.note.to_s }
  end

  def prompt(snapshot)
    <<~PROMPT
      You are TurnPilot, a live queue-ops copilot for a walk-in shop. The counter camera sees
      customers lining up, but NO orders have been started yet — the kitchen may not have
      noticed the queue.

      Reply with ONLY a JSON object (no prose):
        "advise": JSON boolean — true if staff should start taking/prepping orders now.
        "text": one short imperative sentence to staff.
        "rationale": brief reason (cite the visible queue + nothing cooking).
        "suggested_action": short snake_case action, e.g. start_taking_orders.

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
