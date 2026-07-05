class AdvisoriesController < ApplicationController
  before_action :set_advisory

  def accept
    @advisory.accepted!
    learned_threshold.record_accept!   # staff agreed → drift sensitivity back toward baseline
    broadcast
    head :ok
  end

  def override
    @advisory.overridden!
    learned_threshold.record_override! # staff rejected → advise less on similar situations
    broadcast
    toast("Got it — raising the alert threshold for this shop.")
    head :ok
  end

  private

  def set_advisory
    @advisory = Advisory.find(params[:id])
  end

  def learned_threshold
    # Use the advisory's own shop_id — shop-level advisories (open_server) have no order.
    ShopThreshold.for(@advisory.shop_id)
  end

  def broadcast
    Turbo::StreamsChannel.broadcast_replace_to(
      "console",
      target: ActionView::RecordIdentifier.dom_id(@advisory),
      partial: "advisories/advisory", locals: { advisory: @advisory }
    )
    # Refresh the status strip so the learned "advising after ~Xm" threshold visibly moves
    # as staff Accept/Override — the copilot adapting, on screen.
    Turbo::StreamsChannel.broadcast_replace_to(
      "console", target: "status", partial: "console/status"
    )
  end

  def toast(message)
    Turbo::StreamsChannel.broadcast_append_to(
      "console", target: "toast", partial: "console/toast", locals: { message: message }
    )
  end
end
