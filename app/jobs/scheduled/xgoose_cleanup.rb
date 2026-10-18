# frozen_string_literal: true
module ::Jobs
  class XgooseCleanup < ::Jobs::Scheduled
    every 5.minutes
    def execute(args)
      DiscourseXgoose::Quota.reap!
      cutoff = SiteSetting.xgoose_log_retention_days.days.ago
      DiscourseXgoose::Session.where("created_at < ?", cutoff).find_each(&:destroy!)
      DiscourseXgoose::Usage.where("day < ?", cutoff.to_date).delete_all
    end
  end
end
