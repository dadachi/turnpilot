class MakeAdvisoriesShopScoped < ActiveRecord::Migration[8.1]
  def change
    add_column :advisories, :shop_id, :uuid   # loose ref; set for every advisory
    change_column_null :advisories, :order_id, true # shop-level advisories (e.g. open_server) have no order
  end
end
