# Shop-level advisory: when the kitchen is falling behind — more orders cooking than it's
# completing — suggest opening another prep station. Uses only honest throughput signals
# (backlog + recent completions from staff timestamps); no per-order, no join, no Gemma veto
# bypass. Suppressed for a window after each firing so it doesn't spam every tick.
class OpenServerAdvisor
  WINDOW = 10.minutes
  BACKLOG_MIN = 5 # need a real backlog before suggesting more staff

  def self.for(shop_id, now: Time.current) = new(shop_id, now:).call

  def initialize(shop_id, now: Time.current)
    @shop_id = shop_id
    @now = now
  end

  def call
    return nil unless overwhelmed?
    return nil if recently_advised?

    result = GemmaClient.advise(prompt(snapshot), temperature: 0.5)
    return nil unless Advisory.advise?(result["advise"])

    advisory = Advisory.create!(
      kind: "open_server", status: :pending, shop_id: @shop_id,
      text: result["text"].to_s, rationale: result["rationale"].to_s,
      suggested_action: result["suggested_action"].to_s
    )
    broadcast(advisory)
    advisory
  rescue GemmaClient::Error => e
    Rails.logger.warn("[OpenServerAdvisor] #{e.message}")
    nil
  end

  private

  def cooking = Order.cooking_count(@shop_id, @now)
  def completions = Order.completions_in(@shop_id, WINDOW, @now)

  # Falling behind: a real backlog, and it's bigger than what was cleared this window.
  def overwhelmed?
    cooking >= BACKLOG_MIN && cooking > completions
  end

  def recently_advised?
    Advisory.where(shop_id: @shop_id, kind: "open_server")
            .where(created_at: Advisory::SUPPRESSION_WINDOW.ago..).exists?
  end

  def snapshot
    {
      shop: "Cafe demo",
      cooking_now: cooking,
      completed_last_10_min: completions,
      baseline_cook_min: (Order.baseline_cook_seconds(@shop_id) / 60.0).round(1)
    }
  end

  def prompt(snapshot)
    <<~PROMPT
      You are TurnPilot, a live queue-ops copilot for a walk-in shop. The kitchen is falling
      behind — more orders are cooking than are being completed — so waits are growing.

      Reply with ONLY a JSON object (no prose, no markdown) with these keys:
        "advise": a JSON boolean — exactly true or false, never a word. true if staff should
                  add prep capacity now; false if the backlog is likely to clear on its own.
        "text": one short imperative sentence to staff.
        "rationale": one short plain-English sentence a manager gets instantly — that the
                     kitchen is falling behind because more orders are cooking than are
                     finishing, so waits are growing. Don't just list raw counts.
        "suggested_action": a short snake_case action, e.g. open_prep_station.

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
