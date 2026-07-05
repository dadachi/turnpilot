# Receives a camera frame from the console, derives a COARSE observation via local Gemma
# vision, persists only that signal, and discards the frame. The frame never touches the DB,
# disk, or logs (`:frame` is filtered in filter_parameter_logging.rb; the model has no blob
# column). Inert when vision returns nil (camera blocked / Ollama down / unparseable).
class VisionObservationsController < ApplicationController
  def create
    read = VisionClient.observe(strip_data_uri(params[:frame].to_s))
    sid = current_shop_id

    if read && sid
      VisionObservation.create!(
        shop_id: sid,
        people_present: read["people_present"],
        queue_level: read["queue_level"],
        note: read["note"],
        observed_at: Time.current
      )
      VisionObservation.prune!
    end

    head :ok # frame is now out of scope and gone; nothing about it is retained
  end

  # Deterministic demo: seed a camera scenario so the vision advisories fire on cue without a
  # live camera. The next Replayer.tick turns it into a real-Gemma advisory.
  def simulate
    Replayer.simulate_vision(params[:scenario])
    redirect_to console_path
  end

  private

  # Single-shop demo: attribute observations to the shop that has orders.
  def current_shop_id
    Order.where.not(shop_id: nil).pick(:shop_id)
  end

  def strip_data_uri(str)
    str.sub(%r{\Adata:image/\w+;base64,}, "")
  end
end
