# frozen_string_literal: true
module DiscourseXgoose
  # Administrators only, including when the chat feature is disabled.
  class AdminController < ::Admin::AdminController
    skip_before_action :check_xhr
    skip_before_action :preload_json
    def index
      @sessions = Session.order(created_at: :desc)
      @sessions = @sessions.where(user_id: params[:user_id].to_i) if params[:user_id].present?
      if params[:status].present?
        @sessions = @sessions.where(id: Request.where(status: params[:status]).select(:session_id))
      end
      @sessions = @sessions.where("created_at >= ?", params[:after].to_date) if params[
        :after
      ].present?
      @sessions = @sessions.where("created_at < ?", params[:before].to_date + 1) if params[
        :before
      ].present?
      @sessions =
        @sessions
          .limit(50)
          .offset(params[:page].to_i.clamp(0, 10_000) * 50)
          .includes(:user, :requests)
      render layout: false
    rescue ArgumentError
      raise Discourse::InvalidParameters.new(:after)
    end
    def show
      @session = Session.find(params[:id])
      @requests = @session.requests.order(:id)
      @events = @session.events.order(:sequence, :id)
      @complete = Transcript.complete?(@requests, @events)
      @reasons = Transcript.reasons(@requests, @events)
      respond_to do |format|
        format.html { render layout: false }
        format.json do
          render json: {
                   session: @session.as_json(only: %i[id user_id created_at updated_at]),
                   complete: @complete,
                   reasons: @reasons,
                   timeline: Transcript.timeline(@requests, @events),
                   note: I18n.t("xgoose.admin.client_note"),
                   requests:
                     @requests.as_json(
                       only: %i[
                         id
                         session_id
                         user_id
                         request_id
                         turn_id
                         model
                         purpose
                         first_token_ms
                         upstream_status
                         status
                         messages
                         response_message
                         reserved_tokens
                         charged_tokens
                         charged_microusd
                         reserved_microusd
                         pricing_rates
                         provider_usage
                         estimated
                         duration_ms
                         error_code
                         created_at
                         updated_at
                       ],
                     ),
                   client_reported_events:
                     @events.as_json(only: %i[event_id turn_id sequence kind payload created_at]),
                 }
        end
        format.text do
          lines = Transcript.text(@session, @requests, @events)
          send_data lines,
                    type: "text/plain; charset=utf-8",
                    filename: "xgoose-#{@session.id}.txt",
                    disposition: "attachment"
        end
      end
    end
    def destroy
      session = Session.find(params[:id])
      session.with_lock do
        raise Discourse::InvalidAccess if session.requests.where(status: "reserved").exists?
        session.destroy!
      end
      render json: { ok: true }
    end
  end
end
