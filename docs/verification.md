# Verification

Checks below were actually run. Syntax checks alone are not a compatibility claim.

- Local Discourse `release/2026.9` at `bb66372d59c4d32d65752cc9fe651ae7bc868397`, in the official ARM64 development container.
- Both schema migrations completed in test and development PostgreSQL databases.
- **26 Rails/RSpec examples passed**, covering login, foreign-session rejection, administrator-only pages and exports, private-category and private-message access with two accounts, validated/redacted image inputs, dollar reservations and settlement, price snapshots, cache pricing, UTC resets, reservation expiry, Redis concurrency, split SSE, partial output, disconnects, and upstream errors.
- **Eight JavaScript tests passed**, covering read-only tools, private-message opt-in, long-post continuation, abort/429 handling, HTML extraction, image context estimates, and the actual Pi automatic-compaction hook with preserved image input and no duplicate replies.
- **Live OpenAI `gpt-6-luna` browser test passed** using synthetic forum content and a generated test image. The test exercised search, reading posts, exact source URLs, image recognition (`GOOSE-714`), remembered context (`PROJECT-MAPLE-927`) after automatic summaries, dollar accounting, administrator transcript completeness, image redaction, local history restoration, refresh/new-chat behavior, and account-isolated history. Session 49 completed 11 model requests, with two automatic summaries, at **$0.002294** under the configured provider rates. The API key remained server-side and was not committed.
- The deterministic browser suite covers guest guidance, the complete Pi/tool/proxy/audit loop, Chinese mobile/dark layout, and a deliberately delayed first token. See the repository checks for the current run.

GitHub's integration matrix tests `release/2026.9` and `latest` with the official Discourse plugin workflow. The earlier baseline passed both targets; current changes must pass the same matrix before an installable release is tagged. GitHub workflow runs are the authoritative record for their specific commit.

Local browser screenshots contain synthetic fixtures only. The default browser suite uses a local HTTPS model mock. The separate live suite requires explicit `XGOOSE_REAL_API=1` opt-in and spends provider credit. Provider compatibility requires streaming OpenAI Chat Completions with vision and tool calling; other providers and production deployments have not been validated.
