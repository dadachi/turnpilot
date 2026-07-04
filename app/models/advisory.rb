class Advisory < ApplicationRecord
  belongs_to :order

  # kind: which advisory type (v1: "walk_away_risk"; later: open_server, eta, no_show)
  enum :status, { pending: 0, accepted: 1, overridden: 2 }

  scope :recent, -> { order(created_at: :desc) }
end
