# Contributing

Please open an issue describing the forum behavior you want to improve. Keep changes focused on read-only research inside Discourse.

1. Use an isolated Discourse development forum and synthetic content.
2. Run `npm ci && npm run check` and the relevant Discourse RSpec tests.
3. Regenerate the browser bundle after editing `frontend/` or dependency versions.
4. Add English and Simplified Chinese strings for visible UI changes.
5. Include relevant screenshots for panel changes and permission/limit tests for backend changes.

Never include provider keys, real private messages, forum session cookies, or production audit exports in issues or pull requests. New contributions are under GPL-2.0-or-later; retain applicable third-party notices.
