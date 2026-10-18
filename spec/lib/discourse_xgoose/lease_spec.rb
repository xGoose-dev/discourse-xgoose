# frozen_string_literal: true
require "rails_helper"
RSpec.describe DiscourseXgoose::Lease do
  fab!(:user)
  fab!(:other_user, :user)
  it "enforces a per-user lease and a site-wide limit, including staff" do
    SiteSetting.xgoose_site_concurrency = 1
    first = described_class.new(user, SecureRandom.uuid)
    first.acquire!
    expect { described_class.new(user, SecureRandom.uuid).acquire! }.to raise_error(DiscourseXgoose::Error, "busy")
    expect { described_class.new(other_user, SecureRandom.uuid).acquire! }.to raise_error(DiscourseXgoose::Error, "busy")
    first.release!
    next_lease = described_class.new(other_user, SecureRandom.uuid)
    expect { next_lease.acquire! }.not_to raise_error
    next_lease.release!
  ensure
    first&.release!
    next_lease&.release!
  end
end
