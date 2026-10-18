# frozen_string_literal: true
# Only for an isolated development database. Never run against a real community.
abort "Development only" unless Rails.env.development?
SiteSetting.title = "xGoose Community"
SiteSetting.site_description = "A local development forum for xGoose"
SiteSetting.xgoose_enabled = true
SiteSetting.xgoose_api_base_url = "https://localhost:9443/v1"
SiteSetting.xgoose_api_key = "local-mock-only"
SiteSetting.xgoose_model = "xgoose-mock"
SiteSetting.xgoose_daily_tokens = 1_000_000
SiteSetting.allow_user_locale = true
SiteSetting.disable_emails = "non-staff"
SiteSetting.min_first_post_typing_time = 0
SiteSetting.default_locale = "en"
user =
  User.find_by(username: "xgoose_demo") ||
    User.create!(
      username: "xgoose_demo",
      email: "xgoose-demo@example.invalid",
      password: ENV.fetch("XGOOSE_TEST_PASSWORD"),
      active: true,
      approved: true,
      trust_level: 4,
      admin: true,
    )
user.activate
unless Topic.exists?(title: "Building a helpful community knowledge base")
  post =
    PostCreator.create!(
      user,
      title: "Building a helpful community knowledge base",
      raw:
        "Our community keeps practical answers in public discussions. Before answering a question, search for related posts, read the original context, and link to the specific sources. A useful summary explains where members agree and where their experiences differ.",
      skip_validations: true,
    )
  PostCreator.create!(
    user,
    topic_id: post.topic_id,
    raw:
      "For long discussions, read beyond the opening post. New replies may correct outdated advice. Include dates when summarizing changes and say clearly when the available evidence is incomplete.",
    skip_validations: true,
  )
  PostCreator.create!(
    user,
    title: "How to find reliable answers in forum discussions",
    raw:
      "Search using a few specific terms. Open multiple relevant topics and compare the actual posts. Link to the post number, rather than just a topic title. Respect the permissions of private discussions.",
    skip_validations: true,
  )
end
puts "Synthetic development fixture ready"
