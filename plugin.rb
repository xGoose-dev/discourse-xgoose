# frozen_string_literal: true
# name: discourse-xgoose
# about: A browser-side research agent for your Discourse community.
# version: 0.2.0
# authors: xGoose
# url: https://github.com/xGoose-dev/discourse-xgoose
# required_version: 2026.9.0

enabled_site_setting :xgoose_enabled
register_asset "stylesheets/xgoose.scss"

module ::DiscourseXgoose
  PLUGIN_NAME = "discourse-xgoose"
end
require_relative "lib/discourse_xgoose/engine"

after_initialize do
  add_admin_route("xgoose.admin.title", "discourse-xgoose", { use_new_show_route: true })
  # Chat content belongs in the private audit tables, never in Rails request logs.
  ActiveRecord::Base.filter_attributes += %i[messages response_message payload]
  Rails.application.config.filter_parameters += %i[messages tools events content arguments reason]
end
