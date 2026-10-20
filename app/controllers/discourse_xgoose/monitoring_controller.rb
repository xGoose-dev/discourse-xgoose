# frozen_string_literal: true
module DiscourseXgoose
  class MonitoringController < ::Admin::AdminController
    # Native admin routes return the Discourse shell for HTML, JSON for data.
    def overview
      render json: report.overview
    end
    def users
      render json: report.users
    end
    def user
      user = User.find(params[:id])
      scoped = Report.new(params.merge(user_id: user.id))
      changes = BudgetChange.where(user_id: user.id).order(id: :desc).limit(50)
      admins = User.where(id: changes.map(&:admin_id)).pluck(:id, :username).to_h
      render json: {
               user: {
                 id: user.id,
                 username: user.username,
               },
               quota: Quota.snapshot(user),
               report: scoped.overview,
               changes:
                 changes
                   .as_json(
                     only: %i[
                       id
                       user_id
                       admin_id
                       kind
                       reason
                       before_values
                       after_values
                       day
                       created_at
                     ],
                   )
                   .map { |r| r.merge("admin_username" => admins[r["admin_id"]]) },
               recent_sessions:
                 Session
                   .where(id: scoped.metrics.select(:session_id))
                   .order(id: :desc)
                   .limit(20)
                   .as_json(only: %i[id created_at complete]),
               recent_errors:
                 scoped
                   .metrics
                   .where.not(error_code: nil)
                   .order(id: :desc)
                   .limit(20)
                   .as_json(
                     only: %i[id session_id user_id model status error_code reason created_at],
                   ),
               rejections:
                 scoped
                   .rejections
                   .order(id: :desc)
                   .limit(20)
                   .as_json(
                     only: %i[id session_id user_id model status error_code reason created_at],
                   ),
             }
    end
    def change_budget
      raise Discourse::InvalidAccess unless request.headers["Origin"] == Discourse.base_url
      user = User.find(params[:id])
      Budget.change!(current_user, user, params.permit(:operation_id, :kind, :amount_usd, :reason))
      render json: { quota: Quota.snapshot(user) }
    end
    def sessions
      scope = Session.where(id: report.metrics.select(:session_id)).includes(:user)
      scope = scope.where(id: positive_id!(:session_id)) if params[:session_id].present?
      if params[:request_id].present?
        scope =
          scope.where(
            id: Request.where(request_id: params[:request_id].to_s.first(100)).select(:session_id),
          )
      end
      scope = scope.where(complete: params[:complete] == "true") if %w[true false].include?(
        params[:complete],
      )
      if params[:reason].present?
        scope = scope.where("integrity_reasons ? :reason", reason: params[:reason].to_s.first(100))
      end
      if params[:error_code].present?
        scope =
          scope.where(
            id:
              report
                .metrics
                .where(error_code: params[:error_code].to_s.first(100))
                .select(:session_id),
          )
      end
      if params[:expired] == "true"
        scope =
          scope.where(
            id:
              Request
                .where(status: "reserved")
                .where("expires_at < ?", Time.current)
                .select(:session_id),
          )
      end
      scope = scope.where("xgoose_sessions.id < ?", positive_id!(:cursor)) if params[
        :cursor
      ].present?
      rows = scope.order(id: :desc).limit(51).to_a
      more = rows.length > 50
      rows = rows.first(50)
      costs = Metric.where(session_id: rows.map(&:id)).group(:session_id).sum(:charged_microusd)
      calls = Metric.where(session_id: rows.map(&:id)).group(:session_id).count
      render json: {
               sessions:
                 rows.map { |s|
                   {
                     id: s.id,
                     user_id: s.user_id,
                     username: s.user&.username,
                     created_at: s.created_at,
                     updated_at: s.updated_at,
                     complete: s.complete,
                     reasons: s.integrity_reasons,
                     cost: costs[s.id].to_i,
                     calls: calls[s.id].to_i,
                   }
                 },
               next_cursor: more ? rows.last.id : nil,
             }
    end
    def rejections
      scope = report.rejections
      scope = scope.where(reason: params[:reason]) if params[:reason].present?
      scope = scope.where("id < ?", positive_id!(:cursor)) if params[:cursor].present?
      rows = scope.order(id: :desc).limit(51).to_a
      more = rows.length > 50
      rows = rows.first(50)
      names = User.where(id: rows.map(&:user_id)).pluck(:id, :username).to_h
      render json: {
               rejections:
                 rows.map { |r|
                   r.as_json(only: %i[id user_id session_id reason model created_at]).merge(
                     username: names[r.user_id],
                   )
                 },
               next_cursor: more ? rows.last.id : nil,
             }
    end

    private

    def report
      @report ||= Report.new(params)
    end
    def positive_id!(name)
      value = Integer(params[name].to_s, exception: false)
      raise Discourse::InvalidParameters.new(name) unless value && value > 0 && value < 2**63
      value
    end
  end
end
