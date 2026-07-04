# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_04_103123) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "advisories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind"
    t.uuid "order_id", null: false
    t.text "rationale"
    t.integer "status"
    t.string "suggested_action"
    t.string "text"
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_advisories_on_order_id"
  end

  create_table "orders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "customer_read_at"
    t.datetime "joined_at"
    t.datetime "prepared_at"
    t.string "queue_number"
    t.uuid "shop_id"
    t.integer "status"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "advisories", "orders"
end
