class CreateAdvisories < ActiveRecord::Migration[8.1]
  def change
    create_table :advisories, id: :uuid do |t|
      t.references :order, null: false, foreign_key: true, type: :uuid
      t.string :kind
      t.string :text
      t.text :rationale
      t.string :suggested_action
      t.integer :status

      t.timestamps
    end
  end
end
