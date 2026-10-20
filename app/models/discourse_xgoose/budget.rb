# frozen_string_literal: true
module DiscourseXgoose
  class Budget < ActiveRecord::Base
    self.table_name = "xgoose_budgets"
    def self.ensure_for!(user)
      insert_all(
        [{ user_id: user.id, created_at: Time.current, updated_at: Time.current }],
        unique_by: :user_id,
      )
      find_by!(user_id: user.id)
    end
    def self.change!(admin, user, values)
      operation = values[:operation_id].to_s
      raise Discourse::InvalidParameters.new(:operation_id) unless Payload::UUID.match?(operation)
      reason = values[:reason].to_s.strip
      raise Discourse::InvalidParameters.new(:reason) unless reason.length.between?(3, 1000)
      kind = values[:kind].to_s
      raise Discourse::InvalidParameters.new(:kind) unless %w[daily bonus].include?(kind)
      amount = values[:amount_usd]
      amount = nil if kind == "daily" && amount.to_s.strip.empty?
      micros = nil
      unless kind == "daily" && amount.nil?
        decimal = BigDecimal(amount.to_s, exception: false)
        unless decimal&.finite? && decimal >= 0 && decimal <= 1000 &&
                 (decimal * 1_000_000).frac.zero?
          raise Discourse::InvalidParameters.new(:amount_usd)
        end
        micros = (decimal * 1_000_000).to_i
      end
      budget = ensure_for!(user)
      transaction do
        budget.lock!
        previous = BudgetChange.find_by(admin_id: admin.id, operation_id: operation)
        if previous
          raise Discourse::InvalidParameters.new(:operation_id) unless previous.user_id == user.id
          next previous
        end
        usage = Quota.ensure_usage!(user, Time.now.utc.to_date)
        usage.lock!
        before = { daily_microusd: budget.daily_microusd, bonus_microusd: usage.bonus_microusd }
        if kind == "daily"
          budget.update!(daily_microusd: micros)
        else
          # Setting the total bonus is idempotent; only its unspent portion can be removed.
          base = budget.daily_microusd || Pricing.limit
          floor = [usage.used_microusd + usage.reserved_microusd - base, 0].max
          raise Discourse::InvalidParameters.new(:amount_usd) if micros < floor
          usage.update!(bonus_microusd: micros)
        end
        BudgetChange.create!(
          user_id: user.id,
          admin_id: admin.id,
          operation_id: operation,
          kind: kind,
          reason: reason,
          before_values: before,
          after_values: {
            daily_microusd: budget.daily_microusd,
            bonus_microusd: usage.bonus_microusd,
          },
          day: usage.day,
          created_at: Time.current,
        )
      end
    end
  end
end
