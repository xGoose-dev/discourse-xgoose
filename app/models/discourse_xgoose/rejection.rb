# frozen_string_literal: true
module DiscourseXgoose
  class Rejection < ActiveRecord::Base
    self.table_name = "xgoose_rejections"
  end
end
