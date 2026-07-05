class CreateVisionObservations < ActiveRecord::Migration[8.1]
  def change
    create_table :vision_observations, id: :uuid do |t|
      t.uuid :shop_id, null: false                      # loose ref, NOT a foreign key
      t.boolean :people_present, null: false, default: false
      t.integer :queue_level, null: false, default: 0   # none | light | busy (coarse band)
      t.string :note                                     # Gemma's one-liner (no PII by prompt design)
      t.datetime :observed_at, null: false
      # NOTE: deliberately NO image/blob column — the schema itself enforces "frames are never stored".

      t.timestamps
    end
    add_index :vision_observations, [ :shop_id, :observed_at ]
  end
end
