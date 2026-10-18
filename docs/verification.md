# Verification

This file records checks actually completed; a passing syntax check alone is not a compatibility claim.

- Local Discourse `release/2026.9` at `bb66372d59c4d32d65752cc9fe651ae7bc868397`, in the official ARM64 development container.
- PostgreSQL schema migration completed in clean test and development databases.
- 20 Rails/RSpec examples passed, covering logged-in access, foreign-session rejection, admin-only exports, payload restrictions, quota settlement and expiry, namespaced Redis leases, and a streamed HTTPS completion with audit usage.
- Six browser-tool unit tests passed, covering search scope, explicit private-message opt-in, long-post continuation metadata, abort propagation, and text extraction.
- Three Playwright browser integration scenarios passed: login guidance, full Pi → forum tools → Rails → HTTPS mock → transcript export, and Chinese mobile/dark-theme layout.
- The `latest` CI target is being validated before tagging a release. The repository remains a release candidate until that check passes.

The local browser environment uses synthetic posts, a synthetic account, and a deterministic HTTPS model mock. It does not access a production forum or send forum content to a paid LLM. Real-provider compatibility depends on that provider's implementation of OpenAI streaming Chat Completions and tool calling.
