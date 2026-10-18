# frozen_string_literal: true
module DiscourseXgoose
  class Request < ActiveRecord::Base
    self.table_name = "xgoose_requests"
    self.filter_attributes += %i[messages response_message]
    belongs_to :session, class_name: "DiscourseXgoose::Session"
  end
end
