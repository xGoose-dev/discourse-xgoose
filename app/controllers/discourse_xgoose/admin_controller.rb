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
      @sessions = @sessions.where("created_at >= ?", params[:after].to_date) if params[:after].present?
      @sessions = @sessions.where("created_at < ?", params[:before].to_date + 1) if params[:before].present?
      @sessions = @sessions.limit(50).offset(params[:page].to_i.clamp(0, 10000) * 50).includes(:user)
      render layout: false
    rescue ArgumentError
      raise Discourse::InvalidParameters.new(:after)
    end
    def show
      @session = Session.find(params[:id])
      @requests = @session.requests.order(:id)
      @events = @session.events.order(:sequence, :id)
      @complete = Transcript.complete?(@requests, @events)
      respond_to do |format|
        format.html { render layout: false }
        format.json { render json: { session: @session.as_json(only: %i[id user_id created_at updated_at]), complete: @complete,
          note: I18n.t("xgoose.admin.client_note"), requests: @requests.as_json(only: %i[id session_id user_id request_id turn_id model status messages response_message reserved_tokens charged_tokens estimated duration_ms error_code created_at updated_at]), client_reported_events: @events.as_json(only: %i[event_id turn_id sequence kind payload created_at]) } }
        format.text do
          lines = ["xGoose transcript", "Session: #{@session.id}; user: #{@session.user_id}; complete: #{@complete}", I18n.t("xgoose.admin.client_note")]
          @requests.each do |r|
            lines << "\nREQUEST #{r.request_id} (#{r.status}; #{r.charged_tokens} tokens; estimated=#{r.estimated})"
            lines << "Input snapshot (includes context from earlier requests):"
            r.messages.each { |m| lines << "#{m['role']}: #{JSON.generate(m.except('role'))}" }
            lines << "assistant: #{JSON.generate(r.response_message)}"
            lines << "error: #{r.error_code}" if r.error_code
          end
          @events.each { |e| lines << "client_reported [#{e.sequence}] #{e.kind}: #{JSON.generate(e.payload)}" }
          send_data lines.join("\n"), type: "text/plain; charset=utf-8", filename: "xgoose-#{@session.id}.txt", disposition: "attachment"
        end
      end
    end
    def destroy
      session = Session.find(params[:id])
      raise Discourse::InvalidAccess if session.requests.where(status: "reserved").exists?
      session.destroy!
      render json: { ok: true }
    end
  end
end
