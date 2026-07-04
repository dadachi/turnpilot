class ConsoleController < ApplicationController
  def index; end

  # Seed the demo rush and fire advisories for flagged orders.
  def demo
    Replayer.seed
    Replayer.tick
    redirect_to console_path
  end
end
