class Advisory < ApplicationRecord
  # Shop-scoped; `order` is optional because some advisories are shop-level (e.g. open_server).
  belongs_to :order, optional: true

  # kind: which advisory type (v1: "walk_away_risk"; later: open_server, eta)
  enum :status, { pending: 0, accepted: 1, overridden: 2 }

  # After an Override, quiet similar advisories (same order + kind) for this long.
  SUPPRESSION_WINDOW = 5.minutes

  scope :recent, -> { order(created_at: :desc) }

  # Coerce a model's `advise` field to a strict boolean. Gemma occasionally returns a string
  # ("false", "no") or a label instead of a JSON boolean, so accept those; default to
  # advising whenever the value is ambiguous, so a fuzzy response never drops a real alert.
  def self.advise?(value)
    return value if [ true, false ].include?(value)

    !%w[false no 0 none skip never].include?(value.to_s.strip.downcase)
  end
end
