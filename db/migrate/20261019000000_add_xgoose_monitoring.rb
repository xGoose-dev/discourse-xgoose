# frozen_string_literal: true
class AddXgooseMonitoring < ActiveRecord::Migration[7.2]
  def up
    add_column :xgoose_usage, :bonus_microusd, :bigint, null: false, default: 0
    add_column :xgoose_sessions,
               :integrity_reasons,
               :jsonb,
               null: false,
               default: ["legacy_unchecked"]
    add_column :xgoose_sessions, :complete, :boolean, null: false, default: false
    add_column :xgoose_requests, :purpose, :string, null: false, default: "unknown"
    add_column :xgoose_requests, :first_token_ms, :integer
    add_column :xgoose_requests, :upstream_status, :integer
    create_table :xgoose_budgets do |t|
      t.integer :user_id, null: false
      t.bigint :daily_microusd
      t.timestamps
    end
    add_index :xgoose_budgets, :user_id, unique: true
    create_table :xgoose_budget_changes do |t|
      t.integer :user_id, null: false
      t.integer :admin_id, null: false
      t.string :operation_id, null: false
      t.string :kind, null: false
      t.text :reason, null: false
      t.jsonb :before_values, null: false, default: {}
      t.jsonb :after_values, null: false, default: {}
      t.date :day, null: false
      t.datetime :created_at, null: false
    end
    add_index :xgoose_budget_changes, %i[admin_id operation_id], unique: true
    add_index :xgoose_budget_changes, %i[user_id created_at]
    create_table :xgoose_metrics do |t|
      t.bigint :request_id, null: false
      t.bigint :session_id, null: false
      t.integer :user_id, null: false
      t.string :turn_id, null: false
      t.string :model, null: false
      t.string :status, null: false
      t.string :purpose, null: false, default: "unknown"
      t.bigint :charged_microusd, null: false, default: 0
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :cache_tokens
      t.integer :charged_tokens, null: false, default: 0
      t.boolean :estimated, null: false, default: true
      t.integer :duration_ms
      t.integer :first_token_ms
      t.integer :upstream_status
      t.integer :tool_calls, null: false, default: 0
      t.string :error_code
      t.datetime :created_at, null: false
    end
    add_index :xgoose_metrics, :request_id, unique: true
    add_index :xgoose_metrics, %i[created_at user_id]
    add_index :xgoose_metrics, %i[user_id created_at]
    add_index :xgoose_metrics, %i[session_id turn_id]
    create_table :xgoose_rejections do |t|
      t.integer :user_id, null: false
      t.bigint :session_id
      t.string :reason, null: false
      t.string :model, null: false
      t.datetime :created_at, null: false
    end
    add_index :xgoose_rejections, %i[created_at user_id]
    execute <<~SQL
      INSERT INTO xgoose_metrics (request_id, session_id, user_id, turn_id, model, status,
        charged_microusd, charged_tokens, estimated, duration_ms, error_code, created_at,
        input_tokens, output_tokens, cache_tokens, tool_calls)
      SELECT id, session_id, user_id, turn_id, model, status, charged_microusd, charged_tokens,
        estimated, duration_ms, error_code, created_at,
        (provider_usage->>'prompt_tokens')::integer, (provider_usage->>'completion_tokens')::integer,
        (provider_usage->'prompt_tokens_details'->>'cached_tokens')::integer,
        jsonb_array_length(COALESCE(response_message->'tool_calls', '[]'::jsonb))
      FROM xgoose_requests
    SQL
    # Preserve custom retention, including values deliberately set below 30 days.
    execute "UPDATE site_settings SET value = '90' WHERE name = 'xgoose_log_retention_days' AND value = '30'"
  end
  def down
    %i[xgoose_rejections xgoose_metrics xgoose_budget_changes xgoose_budgets].each do |name|
      drop_table name
    end
    remove_column :xgoose_usage, :bonus_microusd
    remove_column :xgoose_sessions, :integrity_reasons
    remove_column :xgoose_sessions, :complete
    %i[purpose first_token_ms upstream_status].each { |name| remove_column :xgoose_requests, name }
  end
end
