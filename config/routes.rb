# frozen_string_literal: true
DiscourseXgoose::Engine.routes.draw do
  get "/config" => "sessions#configuration"
  post "/sessions" => "sessions#create"
  post "/sessions/:id/chat/completions" => "sessions#completion"
  post "/sessions/:id/events" => "sessions#events"
end
Discourse::Application.routes.draw do
  scope "/admin/plugins/discourse-xgoose", constraints: AdminConstraint.new do
    %w[overview users sessions].each do |page|
      get "/#{page}" => "admin/plugins#show",
          :defaults => {
            plugin_id: "discourse-xgoose",
          },
          :constraints => lambda { |request| request.format.html? }
    end
    %w[users sessions].each do |page|
      get "/#{page}/:id" => "admin/plugins#show",
          :defaults => {
            plugin_id: "discourse-xgoose",
          },
          :constraints =>
            lambda { |request|
              request.format.html? && request.path_parameters[:id].to_s.match?(/\A\d+\z/)
            }
    end
    get "/overview.json" => "discourse_xgoose/monitoring#overview"
    get "/users.json" => "discourse_xgoose/monitoring#users"
    get "/users/:id.json" => "discourse_xgoose/monitoring#user", :constraints => { id: /\d+/ }
    put "/users/:id/budget.json" => "discourse_xgoose/monitoring#change_budget",
        :constraints => {
          id: /\d+/,
        }
    get "/sessions.json" => "discourse_xgoose/monitoring#sessions"
    get "/rejections.json" => "discourse_xgoose/monitoring#rejections"
    get "/sessions/:id.json" => "discourse_xgoose/admin#show",
        :defaults => {
          format: :json,
        },
        :constraints => {
          id: /\d+/,
        }
    get "/sessions/:id.txt" => "discourse_xgoose/admin#show",
        :defaults => {
          format: :text,
        },
        :constraints => {
          id: /\d+/,
        }
    delete "/sessions/:id.json" => "discourse_xgoose/admin#destroy", :constraints => { id: /\d+/ }
  end
  mount ::DiscourseXgoose::Engine, at: "/xgoose"
  get "/admin/plugins/xgoose/logs" => "discourse_xgoose/admin#index",
      :constraints => AdminConstraint.new
  get "/admin/plugins/xgoose/:id" => "discourse_xgoose/admin#show",
      :constraints => AdminConstraint.new
  delete "/admin/plugins/xgoose/:id" => "discourse_xgoose/admin#destroy",
         :constraints => AdminConstraint.new
end
