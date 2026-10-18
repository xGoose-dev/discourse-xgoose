# frozen_string_literal: true
class AddXgooseDollarBudgets < ActiveRecord::Migration[7.2]
  def change
    add_column :xgoose_usage, :used_microusd, :bigint, null: false, default: 0
    add_column :xgoose_usage, :reserved_microusd, :bigint, null: false, default: 0
    add_column :xgoose_requests, :reserved_microusd, :bigint, null: false, default: 0
    add_column :xgoose_requests, :charged_microusd, :bigint, null: false, default: 0
    add_column :xgoose_requests, :pricing_rates, :jsonb, null: false, default: {}
    add_column :xgoose_requests, :provider_usage, :jsonb, null: false, default: {}
  end
end
