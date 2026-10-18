# frozen_string_literal: true
class CreateXgooseTables < ActiveRecord::Migration[7.2]
  def change
    create_table :xgoose_sessions do |t|
      t.integer :user_id, null: false
      t.timestamps
    end
    add_index :xgoose_sessions, [:user_id, :created_at]
    create_table :xgoose_requests do |t|
      t.bigint :session_id, null: false
      t.integer :user_id, null: false
      t.string :request_id, null: false
      t.string :turn_id, null: false
      t.string :model, null: false
      t.string :status, null: false, default: "reserved"
      t.jsonb :messages, null: false, default: []
      t.jsonb :response_message, null: false, default: {}
      t.integer :reserved_tokens, null: false
      t.integer :charged_tokens, null: false, default: 0
      t.boolean :estimated, null: false, default: true
      t.integer :duration_ms
      t.string :error_code
      t.datetime :expires_at, null: false
      t.date :usage_date, null: false
      t.timestamps
    end
    add_index :xgoose_requests, :request_id, unique: true
    add_index :xgoose_requests, [:session_id, :turn_id]
    add_index :xgoose_requests, [:status, :expires_at]
    create_table :xgoose_usage do |t|
      t.integer :user_id, null: false
      t.date :day, null: false
      t.bigint :used, null: false, default: 0
      t.bigint :reserved, null: false, default: 0
    end
    add_index :xgoose_usage, [:user_id, :day], unique: true
    create_table :xgoose_events do |t|
      t.bigint :session_id, null: false
      t.string :event_id, null: false
      t.string :turn_id, null: false
      t.integer :sequence, null: false
      t.string :kind, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :xgoose_events, [:session_id, :event_id], unique: true
    add_index :xgoose_events, [:session_id, :sequence]
  end
end
