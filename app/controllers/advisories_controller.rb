class AdvisoriesController < ApplicationController
  before_action :set_advisory

  def accept
    @advisory.accepted!
    broadcast
    head :ok
  end

  def override
    @advisory.overridden!
    broadcast
    head :ok
  end

  private

  def set_advisory
    @advisory = Advisory.find(params[:id])
  end

  def broadcast
    Turbo::StreamsChannel.broadcast_replace_to(
      "console",
      target: ActionView::RecordIdentifier.dom_id(@advisory),
      partial: "advisories/advisory", locals: { advisory: @advisory }
    )
  end
end
