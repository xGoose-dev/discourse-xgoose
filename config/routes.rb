# frozen_string_literal: true
DiscourseXgoose::Engine.routes.draw do
  get "/config" => "sessions#configuration"
  post "/sessions" => "sessions#create"
  post "/sessions/:id/chat/completions" => "sessions#completion"
  post "/sessions/:id/events" => "sessions#events"
end
Discourse::Application.routes.draw do
  mount ::DiscourseXgoose::Engine, at: "/xgoose"
  get "/admin/plugins/xgoose" => "discourse_xgoose/admin#index", constraints: AdminConstraint.new
  get "/admin/plugins/xgoose/:id" => "discourse_xgoose/admin#show", constraints: AdminConstraint.new
  delete "/admin/plugins/xgoose/:id" => "discourse_xgoose/admin#destroy", constraints: AdminConstraint.new
end
