# frozen_string_literal: true
module ::Jobs
  class XgooseCleanup < ::Jobs::Scheduled
    every 5.minutes
    def execute(args)
      DiscourseXgoose::Quota.reap!
      cutoff = SiteSetting.xgoose_log_retention_days.days.ago
      active = DiscourseXgoose::Request.where(status: "reserved").select(:session_id)
      DiscourseXgoose::Session
        .where("updated_at < ?", cutoff)
        .where.not(id: active)
        .find_each do |session|
          session.with_lock do
            if session.updated_at >= cutoff || session.requests.where(status: "reserved").exists?
              next
            end
            session.destroy!
          end
        end
      [
        DiscourseXgoose::Metric,
        DiscourseXgoose::Rejection,
        DiscourseXgoose::BudgetChange,
      ].each do |model|
        scope = model.where("created_at < ?", cutoff)
        scope = scope.where.not(status: "reserved") if model == DiscourseXgoose::Metric
        scope.in_batches(of: 1000).delete_all
      end
      DiscourseXgoose::Usage
        .where("day < ?", cutoff.utc.to_date)
        .where(reserved: 0, reserved_microusd: 0)
        .in_batches(of: 1000)
        .delete_all
      DiscourseXgoose::Session
        .where("integrity_reasons = ?::jsonb", JSON.generate(["legacy_unchecked"]))
        .limit(100)
        .each { |s| DiscourseXgoose::Transcript.refresh!(s) }
      PluginStore.set("discourse-xgoose", "cleanup_at", Time.current.iso8601)
    end
  end
end
