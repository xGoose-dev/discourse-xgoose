# frozen_string_literal: true
module DiscourseXgoose
  class BudgetChange < ActiveRecord::Base
    self.table_name = "xgoose_budget_changes"
    self.filter_attributes += %i[reason]
  end
end
