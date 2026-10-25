# Changelog — busoglabs fork patches

Release notes for the **busoglabs/parse-server-swift** fork. Upstream's own
notes live in `CHANGELOG.md`; this file exists separately so rebases onto
upstream never conflict. One entry per fork tag; each tag = upstream at the
rebase point + every patch listed up to that entry.

Fork discipline: clean patches only, **rebase never merge**; after an upstream
sync, retag as `1.0.4-busog.N+1` and bump the `exact:` pin in
lokalitycloud/busogcloud `Package.swift`. (Consumers pin `exact:` because these
tags are semver prereleases of 1.0.4 — a plain upstream `1.0.4` tag would
outrank them in a `from:` range.)

---

## [1.0.4-busog.6] — 2026-10-25

### Security
- **`checkHeaders` fails closed.** It compared the request's webhook-key header
  with the configured key as two Optionals, so a server started with no key
  accepted any request that sent no header (nil == nil) — every hook open to
  anyone who could reach it. Both must now be non-empty and equal, compared in
  constant time (`webhookKeyMatches`).
- **The environment initialiser refuses to start without
  `PARSE_SERVER_SWIFT_WEBHOOK_KEY`** (missing or empty throws).

---

## [1.0.4-busog.5] — 2026-09-15

### Removed
- **The `ParseServerMemoryStore` patch is gone — 93 lines, measured to do
  nothing.** It swapped Parse-Swift's keychain-backed primitive store for an
  in-memory one, claiming that stopped the macOS keychain dialog after a
  rebuild. It does not, and the reason is structural rather than a bug:
  · an in-memory store is EMPTY on every process start, so the lookup always
    misses and falls straight through to `KeychainStore.shared.get(...)` on the
    next line;
  · `ParseKeychainAccessGroup.setCurrent` and `ParseVersion` write to
    `ParseStorage.shared` and then to `KeychainStore.shared`
    **unconditionally** — side by side, never an else;
  · and `Parse.swift` calls `KeychainStore.shared.deleteAll()`/`.copy(...)`
    directly, with no store indirection at all.
  **Measured, not reasoned:** deleted all three `com.parseSwift.sdk` items, ran
  the sample `App` to a healthy Parse Server, and watched all three reappear.
- The real mitigation is unchanged and lives elsewhere:
  `lokalitycloud/scripts/keychain-reset-parseswift.sh`, called by
  `build-local.sh`, which deletes the items so the new binary creates and owns
  them. Dropping this patch does not bring the dialogs back.

### Note
- Three fork patches now, not four. Every one of them is replayed onto upstream
  forever, so a patch that does nothing is a permanent tax.

---

## [1.0.4-busog.4] — 2026-09-15

### Changed
- **Rebased onto upstream `2e745fd` (28 Jul 2026).** No fork patch changed; all
  four replay cleanly. What came in underneath is upstream housekeeping —
  latest Vapor, the Swift base image to 6.3.3-noble, and two GitHub Actions
  bumps. Verified by a full `xcrun swift build` after the rebase, because the
  Vapor bump is the one that could have broken `Parse+Vapor` or the two
  `ParseHook*+Vapor` files.
- Repo renamed **`busoglabs/parse-server-swift` → `busoglabs/lokality-parse-server-swift`**,
  so it is obvious at a glance that this is our fork and not upstream. The old
  name still redirects, but redirects only survive while nobody re-creates the
  name — the `exact:` pins in lokalitycloud, busogcloud and packcloud were
  updated rather than left to the redirect.

### Note
- ⚠️ The `ParseServerMemoryStore` patch (`feat: in-memory primitive store`) is
  carried forward unexamined. `parse-server/CLAUDE.md` records `primitiveStore`
  as one of four things that *sound* like the macOS keychain fix and are not —
  `ParseKeychainAccessGroup` and `ParseVersion` read `KeychainStore.shared`
  directly, ignoring any configured store. If that applies here too, this is 93
  lines of rebase cost forever for no effect. Worth measuring before the next
  sync.

---

## [1.0.4-busog.3] — 2026-07-21

### Changed
- `PARSE_SERVER_SWIFT_SERVER_URL` is now **validated** (must be a full http(s)
  URL with a host, else boot fails fast with a clear `ParseError`) and resolved
  by a single `resolveServerPathname` helper used by both initializers — a
  set-but-empty or scheme-less value previously slipped through and silently
  killed every hook registration while the app looked healthy.

## [1.0.4-busog.2] — 2026-07-18

### Added
- `PARSE_SERVER_SWIFT_SERVER_URL` — advertised webhook-URL override. Hooks were
  always registered under the bind address, which is unreachable behind a proxy
  or on a PaaS (Heroku binds `0.0.0.0:$PORT`); the override advertises the
  public URL instead.

## [1.0.4-busog.1] — 2026-07-17

### Added
- In-memory primitive store — stops keychain prompts on every recompile
  (`f9c9f3c2`). First clean fork tag after the history rewrite (old messy tip
  recoverable at `530bd02f`).
