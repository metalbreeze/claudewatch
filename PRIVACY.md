# Claude Watch — Privacy Policy

_Last updated: 2026-05-03_

## TL;DR

**Claude Watch does not collect, transmit, or share any personal data.**
Everything stays on your Mac.

## What stays on your device

- Your Claude.ai session cookies, used to call Anthropic's usage
  endpoint on your behalf. Stored in the app's macOS sandbox container.
- Your historical usage data (5-hour and 7-day window snapshots).
  Stored in a local SQLite database inside the same sandbox container.
- Your app preferences (theme, notification thresholds, etc.). Stored
  in macOS UserDefaults.

You can wipe all of the above at any time via _Settings → Data →
Delete All Data_, or by uninstalling the app.

## What we do NOT do

- We do **not** run any servers.
- We do **not** collect telemetry, crash reports, analytics, or
  diagnostic data.
- We do **not** transmit any data to third parties.
- We do **not** share, sell, or rent your information.
- We do **not** use tracking technologies (no advertising IDs,
  fingerprinting, or cross-app tracking).

## Network traffic

The app makes HTTPS requests to `claude.ai` to read your account's
usage statistics. This is the same network traffic your browser
makes when you visit Claude.ai while logged in — Claude Watch
re-uses the session cookies you imported via the in-app
"Import from cURL" flow.

Anthropic's privacy policy applies to that data on Anthropic's
side: <https://www.anthropic.com/legal/privacy>

## Children's privacy

Claude Watch is not directed at children under 13 and does not
knowingly collect data from anyone, regardless of age.

## Changes to this policy

If this policy changes in a way that affects what data is handled
or where it is sent, the change will be noted in the version
released to the Mac App Store and at the top of this document.

## Contact

Questions, concerns, or bug reports: please open an issue at
<https://github.com/metalbreeze/claudewatch/issues>.

## Attribution

Claude Watch is not affiliated with, endorsed by, or sponsored by
Anthropic. "Claude" is a trademark of Anthropic, PBC.
