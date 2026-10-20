# frozen_string_literal: true
module DiscourseXgoose
  class Session < ActiveRecord::Base
    self.table_name = "xgoose_sessions"
    attribute :integrity_reasons, default: -> { ["no_requests"] }
    belongs_to :user
    has_many :requests, class_name: "DiscourseXgoose::Request", dependent: :destroy
    has_many :events, class_name: "DiscourseXgoose::Event", dependent: :destroy
  end
end
