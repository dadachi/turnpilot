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
  end
end
