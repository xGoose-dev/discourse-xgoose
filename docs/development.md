# Development

Use Node.js 22.19+ for the browser bundle, and a working Discourse development environment for Rails and UI integration. Do not run fixture scripts against an existing community.

```sh
npm ci
npm run check
```

This builds the committed, browser-only Pi bundle, exercises the read-only tools, and checks Ruby syntax and YAML. The bundle lives in `assets/javascripts/discourse/lib/xgoose-agent.js`; Discourse includes it through its normal plugin asset compiler. No CDN code loading is required.

Install or symlink the repository at `plugins/discourse-xgoose` in Discourse. Run from the Discourse root:

```sh
LOAD_PLUGINS=1 RAILS_ENV=test bundle exec rake db:migrate
LOAD_PLUGINS=1 RAILS_ENV=test bundle exec rspec plugins/discourse-xgoose/spec
bin/dev
```

The RSpec suite uses WebMock for the HTTPS model endpoint. Tests cover split SSE, permissions, quota reservation and settlement, Redis concurrency, payload validation, and administrator log access. The browser suite uses an isolated development forum and the deterministic local HTTPS provider in `scripts/mock-provider.mjs`; it never calls a paid model.

## Local browser integration

Create a short-lived localhost certificate, trust it **only in your isolated development environment**, and provide its paths as `XGOOSE_MOCK_KEY` and `XGOOSE_MOCK_CERT` to the mock process. It listens on port 9443. The provider URL is `https://localhost:9443/v1` as resolved by Rails.

Set `XGOOSE_TEST_PASSWORD` and run `bundle exec rails runner plugins/discourse-xgoose/scripts/seed-development.rb` in the development forum. It creates synthetic topics and a development-only administrator named `xgoose_demo`, and configures the local provider. Do not use this setup in production.

Run the browser tests from this repository:

```sh
XGOOSE_TEST_BASE_URL=http://localhost:3000 XGOOSE_TEST_PASSWORD=your-local-fixture-password npm run test:browser
```

The tests exercise a real login, Pi tool loop, browser-side forum reads, Rails proxy, mock provider, audit export, translations, and mobile layout. They save screenshots to `test-results/`. Screenshots used in documentation contain only synthetic fixture content.

## Design and interfaces

The panel uses Discourse's typography and theme surfaces. A single xGoose gradient launcher carries the brand; content and citations get most of the space. English strings are the source, with `zh_CN` translations. Avoid storing chat text in browser storage.

Forum tool code belongs in `frontend/tools.js`, the Pi adapter in `frontend/agent.js`, and the Discourse lifecycle adapter in the Ember service. Rails validates the proxy interface independently of browser behavior. Add a tool name to both sides only when its behavior fits the read-only forum scope.

Quota uses a PostgreSQL row lock per user/day and durable reservations. Redis leases use explicitly namespaced keys and expire after the configured timeout plus a grace period. Expired reservations are charged conservatively by cleanup; usage remains independent of transcript content. Never derive billing from client events.
