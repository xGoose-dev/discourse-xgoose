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

The RSpec suite uses WebMock for the HTTPS model endpoint. Tests cover split SSE, permissions, quota reservation and settlement, Redis concurrency, payload validation, and administrator log access. The browser suite uses an isolated development forum and the deterministic local HTTPS provider in `scripts/mock-provider.mjs`; the default suite does not call a paid model.

## Local browser integration

Create a short-lived localhost certificate, trust it **only in your isolated development environment**, and provide its paths as `XGOOSE_MOCK_KEY` and `XGOOSE_MOCK_CERT` to the mock process. It listens on port 9443. The provider URL is `https://localhost:9443/v1` as resolved by Rails.

Set `XGOOSE_TEST_PASSWORD` and run `bundle exec rails runner plugins/discourse-xgoose/scripts/seed-development.rb` in the development forum. It creates synthetic topics and a development-only administrator named `xgoose_demo`, and configures the local provider. Do not use this setup in production.

Run the browser tests from this repository:

```sh
XGOOSE_TEST_BASE_URL=http://localhost:3000 XGOOSE_TEST_PASSWORD=your-local-fixture-password npm run test:browser
```

The tests exercise a real login, Pi tool loop, browser-side forum reads, Rails proxy, mock provider, audit export, translations, and mobile layout. They save screenshots to `test-results/`. Screenshots used in documentation contain only synthetic fixture content.

## Design and interfaces

The panel uses Discourse's typography and theme surfaces. A single xGoose gradient launcher carries the brand; content and citations get most of the space. English strings are the source, with `zh_CN` translations. Local history uses IndexedDB, scoped by origin, base path, and account. Keep the full visible transcript separate from the summarized model context; never store provider credentials in the browser.

Forum tool code belongs in `frontend/tools.js`, the Pi adapter in `frontend/agent.js`, and the Discourse lifecycle adapter in the Ember service. Rails validates the proxy interface independently of browser behavior. Add a tool name to both sides only when its behavior fits the read-only forum scope.

Quota uses a PostgreSQL row lock per user/day and durable micro-USD reservations and per-request price snapshots. Redis leases use explicitly namespaced keys and expire after the configured timeout plus a grace period. Expired reservations are charged conservatively by cleanup; usage remains independent of transcript content. Never derive billing from client events.

## Explicit live-provider validation

Configure a vision-capable OpenAI Chat Completions model in the development forum, including server-only key and accurate prices. The live suite creates a synthetic image, performs real model calls, triggers automatic context summarization, and checks browser history, image redaction, source citations, costs, and administrator exports. It spends provider credit only when explicitly enabled:

```sh
XGOOSE_REAL_API=1 XGOOSE_TEST_PASSWORD=your-local-fixture-password XGOOSE_TEST_MEMBER_PASSWORD=your-local-member-password npx playwright test tests/live-browser.spec.mjs
```

Never put a real key in this command, fixture files, screenshots, or committed configuration. Live tests expect the isolated Luna fixture and a $2 daily budget.

Set `XGOOSE_TEST_MEMBER_PASSWORD` when seeding to create the optional regular-member fixture. Supplying it to the live test also verifies history isolation after switching accounts.


## Native administration and monitoring

Admin UI modules live in `admin/assets/javascripts/discourse/` and use Discourse’s own chart component. JSON reports and budget mutations are under `/admin/plugins/discourse-xgoose/`; HTML routes use the native plugin shell. Legacy audit URLs remain supported.

`xgoose_metrics` contains one bounded, content-free metadata row per reserved model request, updated atomically at settlement and retained independently of transcripts. Rejections have a separate table and never count as model calls. PostgreSQL calculates aggregates and latency percentiles; list endpoints do not load request bodies. `xgoose_usage` is the authoritative daily money ledger. Budget mutations and reservations lock the persistent per-user budget row before the daily ledger; settlement only locks the ledger, request, then session. Admin deletion and retention recheck active requests under the session lock. Client events are never a money source.

The cleanup job runs every five minutes, reaps expired reservations, clears content and metrics after the configured retention, and stores its last-success timestamp. Legacy integrity checks are refreshed in batches. Retained metrics have no cascading foreign key to a transcript.

Run the admin browser suite with the existing synthetic local fixture:

```sh
XGOOSE_TEST_PASSWORD=... XGOOSE_TEST_MEMBER_PASSWORD=... npx playwright test tests/admin-browser.spec.mjs
```

The paid `tests/monitoring-live-browser.spec.mjs` additionally requires `XGOOSE_REAL_API=1`. It exercises zero-budget rejection, an administrator’s temporary grant, a real Luna answer, and consistent report/ledger/transcript values, then restores the original budget policy. Use the fixture accounts only. Finish provider-switch tests by restoring the live model configuration.
