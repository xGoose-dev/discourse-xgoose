# frozen_string_literal: true
module DiscourseXgoose
  class Event < ActiveRecord::Base
    self.table_name = "xgoose_events"
    self.filter_attributes += %i[payload]
  end
end
