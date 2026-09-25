# omarchy-protonpass v1 — Engineering Handoff

**From:** Josh Garcia (garciajosh313@gmail.com) — product owner, plan author, escalation point
**Scope:** Build v1 of `omarchy-protonpass` exactly as specified in `PLAN.md` (rev 2, in this repo).

## What you're building

A Proton Pass quick-access bar widget for Omarchy Quattro (4.x), as a native Quickshell/QML plugin: a bar icon opens a keyboard-first panel that searches Proton Pass login items via Proton's official `pass-cli` and copies usernames, passwords, and TOTP codes to the Wayland clipboard — safely. It complements the official Proton Pass app and CLI; it never bundles, patches, or installs Proton software.

Plugin ID `josh2c.protonpass` · Repo `github.com/josh2c/omarchy-protonpass` · License MIT.

## The plan is the spec

`PLAN.md` is a fully-adjudicated implementation plan. Every product, architecture, security, and scope decision is already made: the keyboard focus model, the copy-in-flight lifecycle, the clipboard-clearing construction, the error-state taxonomy, the versioned JSON contracts, the settings schema, and the task order. It has been audited in three independent passes (implementability, source-verified facts, simplification), and its technical claims were verified against a live Omarchy 4.x install, the `omarchy-github` reference plugin, and the pass-cli v2.3.2 Rust source. The rev-2 header contains the audit log of every change.

**Do not re-litigate decisions or invent behavior.** If you hit something genuinely unspecified, or the plan contradicts what you observe in reality (a newer pass-cli, a changed Omarchy API), stop and flag it to Josh — that's a plan bug to fix in `PLAN.md`, not a judgment call to patch silently.

## Where everything lives

- **Spec**: `PLAN.md` at this repo's root. The single source of truth; there are no other spec documents.
- **Reference plugin**: `~/projects/reference-omarchy-github/` (clone of `github.com/robzolkos/omarchy-github`). Copy its patterns for helper path resolution (`Service.qml:106`), the JSON state envelope, `PanelKeyCatcher` keyboard handling (`Panel.qml:206`), and the `tests/*.sh` style.
- **pass-cli source**: `~/projects/reference-pass-cli/` (clone of `github.com/protonpass/pass-cli`, v2.3.2 snapshot, 2026-08-20). PLAN.md §2.7's classifier strings and the JSON shapes cite exact file:line locations in this tree (e.g. `pass/src/client.rs:133`, `pass-cli/src/commands/item/totp.rs:101`). If Proton has shipped a newer version by the time you start, `git pull` and re-check the cited lines.
- **Omarchy plugin contract** (live on any Omarchy 4.x machine): manifest rules in `/usr/share/omarchy/shell/services/PluginRegistry.qml` and `/usr/bin/omarchy-plugin-validate`; UI components under `/usr/share/omarchy/shell/` (`qs.Ui`: `Panel`, `KeyboardPanel`, `PanelKeyCatcher`, `BarIconButton`); terminal launcher `/usr/bin/omarchy-launch-terminal`; clipboard-history sensitive-skip at `/usr/share/omarchy/shell/plugins/clipboard/capture.sh:15`.
- **Official docs**: pass-cli — https://protonpass.github.io/pass-cli/ · install script — https://proton.me/download/pass-cli/install.sh
- **Fixtures** (created by task T0, required before T3): `tests/fixtures/` in this repo. Do not start the stderr classifier without them.

## How to start

1. Read `PLAN.md` end to end (~15 minutes). Everything below is elaborated there with rationale.
2. **T0 first** — the manual spike. It needs an eligible **paid** Proton account: coordinate with Josh for access. It captures the live pass-cli error strings and JSON shapes into `tests/fixtures/` (several are pre-seeded from source in §2.7; T0 fills the marked gaps: network-down text, plan-gating text, the exact no-lock string, the real ID charset) and measures index latency (which decides risk R3's parallelization fallback).
3. Then T1–T13 in dependency order (§5). Milestones and the critical path are in §7.

## Staffing and parallelization

Sized for **one engineer** (~1.5–2 weeks solo) or **two at most** (~1 week). After T3 freezes the helper's JSON contracts, the two lanes are independent and were designed to be split:

- **Bash lane** (T4–T7): helper `index`/`copy`/`lock`, the clipboard clearer, the behavioral and security test suites — all against mocks.
- **QML lane** (T8–T9): `Service.qml` state machine and `Panel.qml` UI — against the frozen contracts and mock helper via the `OMARCHY_PROTONPASS_HELPER` override.

More than two people will step on each other; don't.

## Non-negotiables

All elaborated with rationale in PLAN.md §3 and enforced by `tests/security-test.sh`:

- Secret values (passwords, usernames, TOTP, any item content) never enter QML, argv, exported env, logs, files, notifications, or JSON responses. The bash helper is the only component that touches them — transiently, in one unexported variable.
- Never pass `--show-secrets`. Never use `eval` or `sh -c` with variables. Opaque IDs only in command lines — item titles and vault names never.
- `wl-copy --sensitive` on every copy; hash-verified timed clear (expiry must never clear content the user copied afterward); the clearer's `exec >/dev/null 2>&1 </dev/null` line is load-bearing — without it, copies hang the UI for the full clear delay (documented in §3.4, with a dedicated test).
- `PASS_LOG_LEVEL=off MUON_LOG_LEVEL=off` on every pass-cli call; never override the user's key-provider, session-dir, credential, or telemetry env vars.
- Login and unlock happen only in a launched terminal running the official CLI; the plugin never handles credentials.
- Every task lands with its tests in the same PR. CI runs with no network, no secrets, and no Proton account.

## Definition of done

- CI green (helper matrix, security suite, source-contract greps, structural manifest checks, shellcheck).
- `omarchy plugin validate .` passes (the real validator — CI deliberately does not replicate it).
- The T12 manual acceptance checklist runs clean on a real paid account.
- Signed `1.0.0` tag; install verified from a clean user via `omarchy plugin add`.

PLAN.md §7's ready-to-implement checklist is the authoritative scope fence — anything not in it is post-v1.

**Questions or plan discrepancies → Josh (garciajosh313@gmail.com).**
