class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders, id: :uuid do |t|
      t.uuid :shop_id
      t.string :queue_number
      t.datetime :joined_at
      t.datetime :prepared_at
      t.datetime :customer_read_at
      t.datetime :completed_at
      t.integer :status

      t.timestamps
    end
  end
end
