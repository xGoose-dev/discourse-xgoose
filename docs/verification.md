# Verification

Checks below were actually run. Syntax checks alone are not a compatibility claim.

## v0.2.0 monitoring upgrade

Validated locally on 2026-10-19 against the same Discourse `release/2026.9` checkout below. All three database migrations completed in development and test.

- **40 Rails/RSpec examples passed**, including administrator-only reports and mutations, blank/zero/overridden budgets, daily bonuses and UTC reset, duplicate submissions, withdrawal protection, price-snapshot accounting, percentile aggregation, pre-model rejections without body logging, transcript deletion without loss of charges, protected active reservations, 90-day cleanup, and legacy integrity refresh.
- A separate two-thread local check submitted the same budget mutation concurrently and verified exactly one audit entry; the original policy was restored.
- **Eight JavaScript tests and `npm run check` passed.** The browser Agent bundle was rebuilt from its pinned dependencies.
- **Five deterministic chat browser scenarios passed**, including the 65-second first-output delay, complete tool-loop audit, Chinese/dark/mobile, local history, and the simplified panel. The native admin browser scenarios separately cover overview charts, user budget changes/restoration, transcript inspection, member access denial, and Chinese mobile layout.
- **Two real Luna end-to-end scenarios passed.** Session 59 performed 12 model calls (10 generation, two context summaries), verified image understanding and research citations, restored history, and recorded **$0.003048**. Session 60 verified a zero-budget rejection, administrator-added funds, subsequent successful generation, and matching user/report/transcript totals: **$0.000084**, HTTP 200, first meaningful output in **1,037 ms**, complete transcript. The two scenarios cost **$0.003132** at the configured rates. Test accounts’ budget policies were restored and the local forum remains on `gpt-6-luna`.

Historical requests have no purpose or first-output measurement; the new UI leaves those values unknown. Deleted transcript content is not reconstructed from retained metrics. Screenshots and live model inputs use the synthetic local forum.

## Earlier chat and image validation

- Local Discourse `release/2026.9` at `bb66372d59c4d32d65752cc9fe651ae7bc868397`, in the official ARM64 development container.
- The first two schema migrations completed in test and development PostgreSQL databases.
- **26 Rails/RSpec examples passed**, covering login, foreign-session rejection, administrator-only pages and exports, private-category and private-message access with two accounts, validated/redacted image inputs, dollar reservations and settlement, price snapshots, cache pricing, UTC resets, reservation expiry, Redis concurrency, split SSE, partial output, disconnects, and upstream errors.
- **Eight JavaScript tests passed**, covering read-only tools, private-message opt-in, long-post continuation, abort/429 handling, HTML extraction, image context estimates, and the actual Pi automatic-compaction hook with preserved image input and no duplicate replies.
- **Live OpenAI `gpt-6-luna` browser test passed** using synthetic forum content and a generated test image. The test exercised search, reading posts, exact source URLs, image recognition (`GOOSE-714`), remembered context (`PROJECT-MAPLE-927`) after automatic summaries, dollar accounting, administrator transcript completeness, image redaction, local history restoration, refresh/new-chat behavior, and account-isolated history. Session 49 completed 11 model requests, with two automatic summaries, at **$0.002294** under the configured provider rates. The API key remained server-side and was not committed.
- **Four deterministic browser scenarios passed**: guest/phone guidance; Pi → forum search/read → Rails → HTTPS mock → complete administrator export (including a long message and automatic scroll); Chinese mobile/dark layout; and a **65-second delay before the first token**, while ordinary forum requests stayed responsive. The delayed call passed the 60-second development web-worker boundary.
- An additional visible in-app-browser test attached an image, verified `GOOSE-714` with a real post citation, restored the saved chat, and continued it with the image context intact. The preview remains configured for `gpt-6-luna`.

Implementation commit `efdcad5` passed both `release/2026.9` and `latest` in the official Discourse plugin workflow: [integration run](https://github.com/xGoose-dev/discourse-xgoose/actions/runs/39098647982). The [build and unit run](https://github.com/xGoose-dev/discourse-xgoose/actions/runs/39098647841) also passed. The subsequent publication commit updates documentation, screenshots, and screenshot output paths only. Local browser UI validation was on `release/2026.9`; the `latest` matrix validates backend compatibility.

Local browser screenshots contain synthetic fixtures only. The default browser suite uses a local HTTPS model mock. The separate live suite requires explicit `XGOOSE_REAL_API=1` opt-in and spends provider credit. Provider compatibility requires streaming OpenAI Chat Completions with vision and tool calling; other providers and production deployments have not been validated.
