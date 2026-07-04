class ConsoleController < ApplicationController
  def index; end

  # Seed the demo rush and fire the first advisories for flagged orders.
  def demo
    Replayer.seed
    Replayer.tick
    redirect_to console_path
  end

  # Advance the simulation one step: fire any newly-flagged advisories (each broadcast via
  # Turbo inside AdvisoryGenerator) and refresh the live status strip. Driven by the
  # console's polling Stimulus controller so the rush plays out live.
  def tick
    Replayer.tick
    broadcast_status
    head :ok
  end

  private

  def broadcast_status
    Turbo::StreamsChannel.broadcast_replace_to("console", target: "status", partial: "console/status")
  end
end
