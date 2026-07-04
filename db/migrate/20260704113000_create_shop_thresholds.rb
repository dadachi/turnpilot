class CreateShopThresholds < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_thresholds, id: :uuid do |t|
      t.uuid :shop_id, null: false                       # loose MyTurnTag ref, not a FK
      t.float :risk_multiplier, null: false, default: 1.5 # learned sensitivity (× baseline wait)
      t.integer :override_count, null: false, default: 0
      t.integer :accept_count, null: false, default: 0

      t.timestamps
    end
    add_index :shop_thresholds, :shop_id, unique: true
  end
end
