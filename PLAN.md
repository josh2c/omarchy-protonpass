# omarchy-protonpass — v1 Implementation Plan

Status: v1.0+v1.1 built; v1.2 addendum (rev 4.1) at end of document · Target: Omarchy Quattro (4.x) · Plugin ID: `josh2c.protonpass` · Repo: `github.com/josh2c/omarchy-protonpass` · License: MIT

All product, architecture, security, and scope decisions are resolved. Facts verified against a live Omarchy 4.x install (`/usr/share/omarchy/shell`, `/usr/bin/omarchy-plugin-validate`), a clone of `robzolkos/omarchy-github`, and the `protonpass/pass-cli` Rust source (v2.3.2, 2026-08). The §2.2 manifest passes `omarchy-plugin-validate` verbatim (tested).

**Rev 2 audit log** — a three-lane audit (implementability / source-verified facts / simplification) produced these changes, all independently verified against sources:
resolved the keyboard-focus model; specified the copy-in-flight lifecycle; the clipboard clearer is now an inline forked subshell (fixing a latent hang: a detached child inheriting helper stdout would block Quickshell's `StdioCollector { waitForEnd: true }` for the full clear delay); the secret path uses a shell variable + sentinel newline strip instead of a `tee >()` pipeline (equal security, far less fragile bash); REVALIDATING collapsed into READY + a `refreshing` flag; SESSION_EXPIRED merged into LOGGED_OUT and OFFLINE+TIMEOUT merged into UNREACHABLE (classifier stays granular; `message` carries the distinction); dropped the `version` helper command, the `vaults[]` contract array, and envelope-wide `warnings`; `manifest-test.sh` slimmed from validator-replica to structural checks; old T10 deleted (its content was its dependencies' acceptance criteria) and the two source-test scripts merged; classifier seeded with real source strings (`No active session`, the locked/expired texts) and freed from an `Error:`-prefix assumption; `session lock` handled as **requiring a pre-existing lock** (`session create-lock`); TOTP JSON shape corrected to a flattened `{"totp": "<code>"}` map (a TOTP countdown is impossible from this data — removed from deferred list); `item list` JSON unwraps `.items`; exit-code discipline corrected to the real reference pattern (0 handled / 2 bad-argv-with-JSON); empty username/email fields confirmed *absent* (never empty-string) in pass-cli source, making the fallback complete; Omarchy's clipboard history confirmed in source to skip `x-kde-passwordManagerHint` offers (R5 downgraded). One audit recommendation was **rejected**: dropping the `pasteOnce` setting — it stays, per the explicit product decision (opt-in, off by default).

**Rev 2.1 (T0 field correction, verified against source and live v2.3.2):** the logged-out string actually seen by vault/item commands is `Error: This operation requires an authenticated client` — a preflight in `pass-cli/src/main.rs:332-341` fires before the deeper `"No active session"` path; the classifier now matches `requires an authenticated client` first and retains `no active session` for deeper paths. Also clarified that `PASS_LOG_LEVEL=off` minimizes but does not silence stderr (default ERROR tracing filter in `logs.rs`); the helper's capture-and-discard of stderr is mandatory, as already designed — no behavioral change, wording corrected.

**Rev 2.2 (T0 live-capture corrections, all verified against source):** (1) `index` now explicitly unwraps `{"vaults":[…]}` and reads `share_id`/`name` (the plan only spelled out the `.items` unwrap). (2) TOTP retrieval switched to the field-less `item totp` form: with `--field totp`, a TOTP stored under any other field name fails with `Field does not exist: totp` (`totp.rs:195`, confirmed live); the field-less form collects all TOTP fields and fails with the expected "No TOTP fields found in this item". (3) **PLAN_INELIGIBLE state removed** — it is unreachable by construction: the eligibility error surfaces only inside the login terminal (which the helper never observes) and login force-logs-out, so subsequent helper calls see plain logged-out; eligibility guidance moved to the setup view, LOGGED_OUT view, and README. (4) "Paid plan" wording tightened: CLI access requires personal **Pass Plus** (or bundles including it) or business **Pass Professional**; business **Pass Essentials is not eligible**. Also: T0 confirmed real IDs (88 chars) pass the allowlist, field output ends in exactly one newline, the flattened TOTP map, the exact no-lock error, and serial index latency of **1.104 s** — risk R3's parallelization fallback is retired; the serial helper stands.

**Rev 2.3 (T0 completion):** the live revoked-session response is a multi-line anyhow chain ending in `non-existent session` (source: `pass/src/muon_ext.rs:31` — pass-cli's own detection string), which the rev 2.2 patterns missed; the classifier now maps `non-existent session` → `logged-out` with the expired-session message, and §2.7 makes explicit that patterns match anywhere in the **full multi-line stderr capture** (anyhow "Caused by:" chains included). Field-less `item totp` success output can carry both `totp` and `totp_uri` keys (both values are generated codes in this command — `TotpOutput::Code` is forced; but the extraction fallback defensively skips `*_uri`-named keys anyway). Confirmed: the weekly self-update check cannot stall helper calls in v2.3.2 (skipped when stderr is captured/non-terminal). T0 is closed: all fixtures captured, identity-free, at `tests/fixtures/`; the disposable CLI session was revoked afterward.

**Rev 2.4 (T3 contract-gap fix):** the §2.5 `command` enum gains `unknown`, permitted only for dispatcher-level argv errors (empty invocation, unrecognized subcommand) where no truthful command name exists; invalid options for a recognized subcommand keep that command's name. Both are exit 2 + JSON; the Service's handling (exit 2 → ERROR) is unchanged. The T1 stub's practice of labeling such errors `doctor` was misleading and is superseded.

**Rev 2.5 (T3-acceptance codification):** `index`'s success state `ready` is now formally enumerated in §2.5 (`ready |` shared error states) — previously implied only by the response example and the §2.6 diagram. Ratifies the interim answer given while T4 was paused. Contracts are frozen as of T3 acceptance; further changes require a schemaVersion discussion, not a rev note.

**Corrections to the original brief** (verified, unchanged from rev 1): manifest requires `entryPoints`; `activation` is dead; single-instance is `barWidget.allowMultiple: false`. pass-cli sessions live in a file under `~/.local/share/proton-pass-cli/.session/` encrypted with a kernel-keyring key (defaults we never override). Session lock is enforced **server-side** — listing and retrieval always need network. Item summaries carry no username preview and no TOTP flag, and are non-secret by source-level contract. `item list` is per-vault. pass-cli has no clipboard command. Field retrieval addresses items by `--share-id`/`--item-id`/`--field` (bare value + `\n` on stdout); titles never enter a command line.

---

## 1. Product definition

### 1.1 Final v1 user experience

A bar icon (Nerd Font key glyph) in the right bar section. Activating it opens a keyboard-first popup.

**Focus model (decided):** the panel opens with the search field focused; typing filters immediately. While search is focused, the `PanelKeyCatcher` intercepts only `↑`/`↓` (move list cursor), `Enter` (copy password of cursor item), and `Esc`; all printable keys go to the search text. Pressing `↓` past intercept-mode or `Tab` moves focus to the list; from the list, `j/k/↑/↓` move, `u`/`p`/`Enter`/`t` copy username/password/password/TOTP, `L` locks, `r` refreshes, and typing any printable character or `/` refocuses search (a `/` refocus does not insert the slash). `Esc` is layered: clear search text → close panel.

1. The item index (titles + vault names) serves instantly from the in-RAM session index; opening the panel triggers a background refresh (`refreshing` flag, footer spinner). First-ever open shows a loading state. The index is fetched only on panel open — never prefetched at bar startup.
2. Every row shows title + vault name in muted text (vault always visible).
3. Actions are explicit — never on mere selection. Usernames, passwords, and TOTP values are never rendered anywhere.
4. Copy feedback is a toast (~3 s, a new toast replaces the old): "Password copied — clears in 45s", or "Username copied…" / "Email copied…" (fallback is named), or "Password copied" when `clipboardClearSeconds` is 0. Failure toasts: "No TOTP on this item", "No username or email on this item", "No session lock configured — run `pass-cli session create-lock`", "Copy failed — check connection and try again" (non-auth failures leave panel state unchanged).
5. Empty results are READY, not errors: zero items shows "No login items found" (plus a hint when `excludeVaults` is set); zero search matches shows "No matches".
6. Clipboard: `wl-copy --sensitive` (Omarchy's clipboard-history capture skips `x-kde-passwordManagerHint` offers — confirmed in shell source), cleared after `clipboardClearSeconds` (default 45) only if the clipboard still holds our value (hash-verified). Paste-once (`-o`) is an opt-in setting, off by default (breaks Electron/browser multi-read paste).

### 1.2 Supported workflows

- Search and copy username / password / TOTP from any active login item across all vaults minus excluded ones.
- Guided setup when pass-cli or wl-clipboard is missing — copyable official install commands only; the plugin never installs anything. Arch note: AUR `proton-pass-cli-bin`; the AUR package literally named `pass-cli` is an unrelated project (README warns).
- Login: panel button launches a terminal running plain `pass-cli login` — the default **web/browser flow** (the only one supporting FIDO2/SSO; no credentials typed in a terminal). Unlock: same pattern with `pass-cli session unlock`. Lock: non-interactive `pass-cli session lock` from the panel — which **requires the user to have created a lock** via `pass-cli session create-lock`; absent one, the panel explains that (toast above). Terminal launch uses `/usr/bin/omarchy-launch-terminal` semantics (`omarchy launch terminal <cmd…>` → argv passthrough, verified).

### 1.3 Unsupported / explicitly deferred

Item create/edit/delete, sharing, attachments, password generation, SSH-agent, aliases, non-login item types, `--show-secrets` in any form, PAT/agent sessions, offline mode, disk-persisted index, fuzzy search, secret display of any kind, `pass-cli run`/`inject`. Post-v1 candidates: non-login types, include-list vault UI, configurable keybindings. (A TOTP countdown is **not** a candidate: `item totp` output carries no period/remaining data.)

### 1.4 Prerequisites and compatibility

Omarchy Quattro/4.x · `pass-cli` ≥ 2.3 on PATH · a Proton plan with CLI access — personal **Pass Plus** (or bundles including it) or business **Pass Professional**; business **Pass Essentials is not eligible** (refs: proton.me/business/pass/pricing, proton.me/support/proton-pass-plans-explained; stated up front in README) · `wl-clipboard`, `jq`, `bash`, `coreutils` (stock on Omarchy) · network for every index refresh and copy.

---

## 2. Technical architecture

### 2.1 Repository layout (final)

```
omarchy-protonpass/
├── manifest.json
├── Panel.qml               # entryPoints.barWidget — bar button + KeyboardPanel popup
├── Service.qml             # sibling component instantiated inside Panel.qml (NOT a service entry point)
├── omarchy-protonpass      # bash helper, executable, resolved relative to Panel.qml
├── README.md
├── LICENSE                 # MIT
├── preview.png
└── tests/
    ├── lib.sh              # asserts, sandbox PATH builder
    ├── mocks/pass-cli      # scenario-driven (MOCK_SCENARIO env)
    ├── mocks/wl-copy       # records argv + sha256(stdin) only
    ├── mocks/wl-paste      # replays configured value
    ├── fixtures/           # captured real stderr strings + JSON shapes (T0)
    ├── helper-test.sh
    ├── security-test.sh
    ├── source-contract-test.sh   # Panel.qml + Service.qml exact-snippet greps (one file)
    └── manifest-test.sh    # structural checks only: valid JSON, referenced files exist, no symlinks
```

No `assets/` (icon is a Nerd Font glyph). No symlinks (validator rejects them). Real manifest validation is `omarchy plugin validate .`, run locally (T1 acceptance) and at the release gate — `manifest-test.sh` deliberately does **not** replicate the unversioned validator.

### 2.2 manifest.json (final — passes `omarchy-plugin-validate` verbatim, tested)

```json
{
  "schemaVersion": 1,
  "id": "josh2c.protonpass",
  "name": "Proton Pass",
  "version": "1.0.0",
  "author": "Josh Garcia",
  "license": "MIT",
  "description": "Quick-access search and copy for Proton Pass logins via the official pass-cli.",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "Panel.qml" },
  "barWidget": {
    "displayName": "Proton Pass",
    "description": "Search Proton Pass logins; copy username, password, or TOTP.",
    "category": "Security",
    "allowMultiple": false,
    "defaultSection": "right",
    "defaults": { "clipboardClearSeconds": 45, "pasteOnce": false, "excludeVaults": "" },
    "schema": [
      { "key": "clipboardClearSeconds", "type": "integer", "label": "Clear clipboard after (seconds)",
        "description": "0 disables automatic clearing.", "defaultValue": 45, "min": 0, "max": 300, "step": 5 },
      { "key": "pasteOnce", "type": "boolean", "label": "Paste once",
        "description": "Clipboard offers the value a single time. Some apps (Electron, browsers) read the clipboard more than once per paste and will fail.", "defaultValue": false },
      { "key": "excludeVaults", "type": "string", "label": "Excluded vaults",
        "description": "Comma-separated vault names to hide from search.", "defaultValue": "" }
    ]
  }
}
```

No `activation` key (dead field). Settings hold no secrets by construction.

### 2.3 Component responsibilities and boundaries

**Panel.qml** — root `Panel` from `qs.Ui` (omarchy-github pattern): `BarIconButton` + `KeyboardPanel` + `PanelKeyCatcher` (`blocked` derived from search focus per the §1.1 focus model). Instantiates `Service { id: svc; settings: root.settings }` and binds only to its non-secret model and state. Launches terminals via `Quickshell.execDetached(["omarchy", "launch", "terminal", "pass-cli", "login"])` / `[..., "session", "unlock"]` — fixed argv arrays, never string-joined. Bar icon: urgent tint in LOGGED_OUT, LOCKED, MISSING_DEPS (states needing user action); normal foreground otherwise, including UNREACHABLE/ERROR (transient). Has no property that could hold a secret.

**Service.qml** — headless sibling `Item`. Owns the state machine, item model, and all helper invocations via `Quickshell.Io.Process` with argv arrays + `StdioCollector { waitForEnd: true }`. Resolves the helper: `Qt.resolvedUrl("omarchy-protonpass").toString().replace(/^file:\/\//, "")`, overridable via `OMARCHY_PROTONPASS_HELPER` for tests. Defensively parses stdout: `JSON.parse` in try/catch, requires `schemaVersion === 1`, known `command` and `state`, type-checks every field; violations → ERROR. **Exit-code discipline** (matches the omarchy-github reference exactly): exit 0 = handled state in JSON; exit 2 = invalid argv, may still carry JSON (treated as ERROR — programmer bug); nonzero without parseable JSON = ERROR. Generation counter on `index`: stale responses discarded; panel close / refresh kills in-flight **index** processes only. **Copy lifecycle (decided):** copy processes are never killed — they run to completion; a panel-wide busy flag blocks starting a second copy while one is in flight; a copy response arriving after panel close suppresses its toast but auth-state transitions still apply. Retains only `itemId, shareId, vaultName, title`; index kept in RAM for the shell session, dropped on lock/logout, refreshed on every panel open.

**omarchy-protonpass helper** — bash, `set -euo pipefail`, no `eval`, argv-only. The *only* component touching secret bytes — transiently, in one unexported shell variable inside a single ~30-line function. Prepends `PASS_LOG_LEVEL=off MUON_LOG_LEVEL=off` to every pass-cli call — these *minimize* logging but do not silence it: pass-cli's `logs.rs` installs a default ERROR-level filter regardless (`with_default(tracing::Level::ERROR)`), so ERROR tracing lines still reach stderr; capturing and discarding pass-cli stderr is therefore mandatory, not belt-and-braces. Never sets key-provider/session-dir/credential/telemetry vars. Every subcommand exits **0** with one JSON document on stdout for all handled states; exit 2 + JSON error for invalid argv. pass-cli calls wrapped in `timeout 20s` (index) / `15s` (copy, lock).

### 2.4 Helper command interface (final)

```
omarchy-protonpass doctor
omarchy-protonpass index   --exclude-vaults "<comma,list>"
omarchy-protonpass copy    --share-id <id> --item-id <id> --field <username|password|totp>
                           --clear-seconds <0..300> [--paste-once]
omarchy-protonpass lock
```

Validation before any execution (violations → exit 2 + `state:"error"` JSON): ids must match `^[A-Za-z0-9+/=_-]{1,256}$` — a conservative allowlist (pass-cli imposes no charset on its opaque ids; base64-like in practice; confirmed against real ids in T0); field is a strict enum; clear-seconds integer 0–300.

- `doctor`: checks `pass-cli`/`wl-copy`/`wl-paste` on PATH, captures `pass-cli --version`, warns on major version ≠ 2.
- `index`: `pass-cli vault list --output json`, unwrapping the `{"vaults":[…]}` wrapper and reading each vault's `share_id` + `name` → drop excluded vaults → per remaining vault `pass-cli item list --share-id <id> --filter-type login --filter-state active --output json`, unwrapping the `{"items":[…]}` wrapper → merge with `vaultName` → emit. `--exclude-vaults` handling: split on commas, **trim surrounding whitespace** from each name, case-sensitive exact match against parsed JSON (vault names containing commas cannot be excluded in v1 — documented); names never enter a command line. Per-vault failure → `warnings[]` + partial results; vault-list-stage failure → classified state.
- `copy`: fetches via `pass-cli item view --share-id X --item-id Y --field <f>`:
  - `username`: try `username`; on failure retry `email`; report `fallbackUsed`. pass-cli source guarantees empty fields are *absent* (serialized only when non-empty), so "Field does not exist" is the complete empty-or-absent signal; defensively, a zero-length retrieved value is also treated as absent. Both missing → `no-field`.
  - `password`: single fetch; missing → `no-field`; an existing password is copied as-is (never fallback-eligible).
  - `totp`: `pass-cli item totp --share-id X --item-id Y --output json` — deliberately **without** `--field`: the field-scoped form fails with `Field does not exist: totp` when the TOTP lives under a custom field name (`totp.rs:195`, confirmed in T0), while the field-less form collects every TOTP field. Output is a serde-flattened map `{"<field-name>": "<6-digit code>"}` (no wrapper, no countdown data); success output can carry both `totp` and `totp_uri` keys (T0-confirmed; both values are generated codes in this command). Extraction: prefer the canonical `totp` key; otherwise the first key **not** ending in `_uri` (defensive — values are codes here, but the suffix skip costs nothing); otherwise the first key. Multi-TOTP items are rare; nondeterministic pick accepted for v1. "No TOTP fields found in this item" → `no-field`.
  - **Secret handling (decided construction):** capture with the sentinel idiom to strip exactly one trailing newline without corrupting values that end in literal newlines —
    `val=$(pass-cli … ; printf x); val=${val%x}; val=${val%$'\n'}` — then `printf '%s' "$val" | wl-copy --sensitive` (plus `-o` when `--paste-once`) and `hash=$(printf '%s' "$val" | sha256sum | cut -d' ' -f1)`; `unset val`. The variable is never exported, never argv, never echoed; exposure class is identical to a pipe buffer (same-UID memory, already accepted in the threat model). Then spawn the clearer (§3.4). Response JSON carries no value.
- `lock`: `pass-cli session lock`. pass-cli requires a pre-existing lock (`session create-lock`); the no-lock failure is classified as `no-lock` and the panel explains it. Success → panel clears model, state LOCKED.

Note on CLI field resolution: pass-cli's `--field` match is case-insensitive and also matches unqualified section-scoped names (e.g. a custom `Extra.username`); acceptable — the resolved value comes from the user's own item.

### 2.5 Versioned JSON contracts (schemaVersion 1)

Common envelope on every response:

```json
{ "schemaVersion": 1, "command": "<doctor|index|copy|lock|unknown>", "state": "<state>",
  "message": "<sanitized, user-displayable>" }
```

`"command": "unknown"` is permitted **only** for dispatcher-level argv errors — an empty invocation or an unrecognized subcommand (exit 2 + `state:"error"`). Invalid options for a *recognized* subcommand keep that subcommand's name (also exit 2 + JSON). The Service treats any exit-2 response as ERROR regardless of `command`, so this distinction exists for debuggability, not control flow.

`doctor` adds `"passCli": {"present": true, "version": "2.3.2"}, "wlClipboard": {"present": true}`; states `ok | missing-deps`.

`index` adds `"items": [ { "itemId": "xyz==", "shareId": "abc==", "vaultName": "Personal", "title": "GitHub" } ]` and `"warnings": []` (index-only; per-vault partial-failure notes); states `ready |` shared. No `vaults` array — nothing consumes it.

Shared error states for `index`/`copy`/`lock`: `cli-missing | logged-out | locked | unreachable | error`. (There is deliberately no plan-eligibility state: the eligibility error surfaces only inside the login terminal, and pass-cli force-logs-out on it, so the helper can only ever observe `logged-out` — eligibility guidance lives in the setup/LOGGED_OUT views and README instead.) `logged-out` covers session-expired (the `message` distinguishes "Not signed in" from "Session expired — sign in again"); `unreachable` covers network failure and timeout (`message` distinguishes). The classifier stays fully granular internally — only the state fan-out is merged.

`copy` adds `"field", "fallbackUsed", "clearSeconds"`; states `copied | no-field |` shared. `lock` states: `locked | no-lock |` shared.

Rules: additive changes only under schemaVersion 1; breaking changes bump it and the Service rejects mismatches. `message` is always helper-authored — never raw pass-cli stderr. Titles/vault names pass through as JSON strings; QML renders them with `textFormat: Text.PlainText` only.

### 2.6 State machine

Service `state` (single enum) plus two orthogonal booleans: `refreshing` (background index in flight while a model exists) and `copyBusy` (panel-wide).

```
INIT ──doctor──▶ MISSING_DEPS            (doctor re-run on every panel open; Recheck)
   └──ok──▶ (first panel open) LOADING ──index──▶ READY
                     ├──▶ LOGGED_OUT      (Sign in → terminal; model cleared)
                     ├──▶ LOCKED          (Unlock → terminal; model cleared)
                     ├──▶ UNREACHABLE     (Retry; stale model kept if one exists)
                     ├──▶ MISSING_DEPS    (on cli-missing from any command; doctor re-run)
                     └──▶ ERROR           (Retry)
READY: panel open or `r` → refreshing=true, background index
   · success → swap model, refreshing=false
   · auth-class failure (logged-out/locked) → clear model, transition
   · unreachable/error → keep model, refreshing=false, staleWarning=true ("Showing cached list — refresh failed")
`r` with no model → LOADING (full fetch).
```

**Recovery-action semantics (decided):** *Retry* = run `index`. *Recheck* = run `doctor`, then `index` if deps pass. Opening the panel in any non-READY, non-LOADING state automatically re-runs that state's recovery command (this is also how return-from-terminal login/unlock is picked up — no IPC needed). Copy results: `copied`/`no-field`/`no-lock`/non-auth failures → toast only, state unchanged; auth-class results → model cleared + transition (even if the panel has closed; only the toast is suppressed).

### 2.7 stderr classification (helper-internal)

pass-cli has no error taxonomy. Classification is one case-insensitive pattern table matched anywhere in the **full multi-line stderr capture** — real failures arrive as anyhow "Caused by:" chains whose decisive string (e.g. `non-existent session`) sits several lines deep. **The classifier must not assume an `Error:` prefix** — only the generic anyhow path prints it; the locked hint and session-expired notice are plain `eprintln!` lines. Seeds below are verified against pass-cli source (file:line in the audit); T0 confirms them against the live binary and fills the marked gaps:

| Signal | State |
|---|---|
| `pass-cli` absent (`command -v` fails) | `cli-missing` |
| `requires an authenticated client` (the preflight in `pass-cli/src/main.rs:332-341` fires before vault/item commands reach deeper paths — **confirmed live in T0** against v2.3.2) | `logged-out` |
| `no active session` (deeper-path string, e.g. settings commands; retained as source-valid) | `logged-out` |
| `session has been invalidated` / `log in again` | `logged-out` (expired `message`) |
| `non-existent session` (revoked session; appears deep in an anyhow "Caused by:" chain — **confirmed live in T0**) | `logged-out` (expired `message`) |
| `session is locked` (full text: "Session is locked. Please unlock your session and try again.") | `locked` |
| `session is not locked` / lock-required text (T0 pins exact no-lock string) | `no-lock` (lock command only) |
| connection/DNS/network text (T0 pins) or `timeout` exit 124 with no output | `unreachable` |
| anything else | `error` |

Raw stderr is never emitted, logged, or forwarded — only the classified state and a canned `message`.

### 2.8 Dependency detection and setup

`doctor` runs at widget activation and on every panel open while in MISSING_DEPS; the index is fetched only on panel open (no prefetch at bar startup). Setup view: copyable fixed commands (official installer `curl -fsSL https://proton.me/download/pass-cli/install.sh | bash`; Arch note re AUR `proton-pass-cli-bin` and the unrelated `pass-cli` package; `sudo pacman -S wl-clipboard`) and the plan-eligibility requirement (Pass Plus / Pass Professional; Pass Essentials excluded — with the two Proton reference links from §1.4).

---

## 3. Security design

### 3.1 Threat model

**Assets**: (A1) secret values in transit helper→clipboard; (A2) the Proton session file + keyring key (owned by pass-cli, never touched); (A3) non-secret item metadata; (A4) the clipboard; (A5) the plugin code as a supply-chain vector (runs unsandboxed inside omarchy-shell).

**Adversaries**: local malware reading clipboards or `/proc` cmdlines; clipboard-history tooling; shoulder surfers; log scrapers; a compromised repo or update; other unsandboxed plugins in the same shell process.

**Accepted residual risk** (documented in README): an attacker with the user's UID already owns the pass-cli session — same-UID process memory (pipe buffers, the helper's transient variable) is inside that boundary and not defended; any Wayland client can read the clipboard while a value is live — the 45s window is exposure minimization, not isolation.

### 3.2 Trust boundaries

```
[QML Panel+Service] —argv/JSON→ [helper bash] —argv→ [pass-cli] —pipe→ [wl-copy]
   no secrets ever              secrets transient      Proton-trusted  compositor
```

QML stays secret-free by construction (also defends against co-resident plugins). The helper's secret path is one short function, fully covered by `security-test.sh`.

### 3.3 Secret lifecycle

Copy trigger → ids + field enum as argv → helper fetches one field → value held in one unexported shell variable (sentinel-captured, exactly one trailing newline stripped) → `printf '%s' | wl-copy --sensitive` → sha256 computed the same way → `unset val` → clearer spawned with the *hash* (never the value) → after `clearSeconds`, clearer hash-compares the live clipboard and clears **only on match** → done. `clearSeconds = 0` spawns no clearer. Secrets never appear in argv (`/proc` scans in tests), exported env, files, logs, JSON, QML, toasts, or test artifacts (mocks record hashes only).

### 3.4 Clipboard ownership and clearing

- `--sensitive` marks the offer `x-kde-passwordManagerHint`; Omarchy's clipboard-history capture explicitly skips such offers (verified in `/usr/share/omarchy/shell/plugins/clipboard/capture.sh` — re-confirmed live in T12).
- **Clearer construction (decided):** an inline backgrounded subshell — no separate script, no re-exec, no handoff protocol. It *inherits* `$hash` and `$secs` as unexported shell variables (invisible to `/proc/*/cmdline` and `/proc/*/environ`, same invisibility as a stdin handoff at far less machinery):

  ```
  ( exec >/dev/null 2>&1 </dev/null
    sleep "$secs"
    cur=$(wl-paste --no-newline 2>/dev/null | sha256sum | cut -d' ' -f1)
    [ "$cur" = "$hash" ] && wl-copy --clear ) &
  disown
  ```

  The `exec >/dev/null 2>&1 </dev/null` line is **load-bearing**: without it the child inherits the helper's stdout pipe and Quickshell's `StdioCollector { waitForEnd: true }` blocks the copy response for the full `clearSeconds` — this is an explicit test case, not a style choice. The orphaned subshell survives helper exit.
- Rapid successive copies need no cancellation bookkeeping: each old clearer fails its hash check harmlessly, so expiry can never clear content copied afterward. Primary selection never touched. The clearer transiently reads the live clipboard to hash it — a short-lived process that writes nothing; the accepted minimal cost of newer-content safety.

### 3.5 Logging and error sanitization

Helper captures pass-cli stderr to a local variable, classifies, discards; writes no logs or temp files. This capture is load-bearing: even with `PASS_LOG_LEVEL=off`, pass-cli's default ERROR filter emits tracing lines (with file/line prefixes) to stderr on every failure path. Service logs only e.g. `"omarchy-protonpass: malformed helper response (command=index)"` — never bodies. All user-visible messages come from fixed tables.

### 3.6 Process-argument and environment rules

All launches use argv arrays; `eval`, `sh -c` with variables, and backtick interpolation are banned and grep-enforced. Titles/vault names never enter command lines. Env additions limited to `PASS_LOG_LEVEL=off`, `MUON_LOG_LEVEL=off`. The secret variable is never `export`ed (grep-enforced).

### 3.7 Metadata retention

In-RAM, session-lifetime; dropped on lock/logout; never on disk. The only metadata at rest is the user-typed `excludeVaults` setting.

### 3.8 Supply chain

Zero dependencies beyond stock Omarchy tooling + user-installed pass-cli; no vendored code; the plugin itself makes no network calls. Branch protection, CI on PRs, signed release tags. Users install with `omarchy plugin add <repo-url>` (validates, never executes plugin code) and update via `omarchy plugin update`, which shows a diff first (verified in `omarchy-plugin-update`). The plugin never bundles, patches, or auto-installs Proton software.

### 3.9 Risk → mitigation summary

| Risk | Mitigation |
|---|---|
| Secret leaks into QML/logs/argv/exported env | Boundary design + `/proc` and output scans + source-contract greps in CI |
| Clipboard sniffing during live window | `--sensitive` + 45s hash-verified clear + opt-in paste-once; residual risk documented |
| Expiry clears the user's newer copy | Hash-compare before clear (explicitly tested) |
| Clearer blocks the copy response (fd inheritance) | Mandatory fd redirection in the clearer + dedicated test |
| Malicious/malformed CLI output | Strict JSON validation, id allowlist, PlainText rendering, no interpolation |
| stderr drift across pass-cli versions | Source-verified + fixture-pinned classifier; unknown text falls to generic `error`+Retry (never mis-acts); doctor warns on unexpected major version |
| Compromised update | Diff-on-update flow, signed tags, tiny surface |

---

## 4. Failure behavior

| State / event | Message | Recovery |
|---|---|---|
| MISSING_DEPS | "Proton Pass CLI not found" + install commands + plan-eligibility note | Copy commands · Recheck (auto on panel open) |
| LOGGED_OUT | "Not signed in to Proton Pass" or "Session expired — sign in again" (per `message`), plus a persistent hint: "Sign-in requires a plan with CLI access (Pass Plus or Pass Professional) — an eligibility error appears in the sign-in terminal otherwise" | **Sign in** (terminal, web login) · Retry (auto on panel open) |
| LOCKED | "Session locked" | **Unlock** (terminal) · Retry (auto on panel open) |
| UNREACHABLE | "Can't reach Proton" or "Proton Pass CLI timed out" (per `message`); stale model kept & marked | Retry (auto on panel open) |
| ERROR | "Something went wrong talking to pass-cli" | Retry |
| READY, zero items | "No login items found" (+ excludeVaults hint if set) | — |
| READY, zero matches | "No matches" | — |
| READY, staleWarning | "Showing cached list — refresh failed" (footer) | `r` |
| copy `no-field` | "No TOTP on this item" / "No username or email on this item" (toast) | — |
| lock `no-lock` | "No session lock configured — run `pass-cli session create-lock`" (toast) | — |
| copy non-auth failure | "Copy failed — check connection and try again" (toast; state unchanged) | — |
| copy auth-class result | Panel transitions (model cleared); toast suppressed if panel closed | as per state |
| Return from login/unlock terminal | Auto-retry on next panel open | automatic |

---

## 5. Implementation tasks

Each task lands with its tests in one PR. ∥ = parallelizable once deps met.

**T0 — Real-world behavior spike** (manual, eligible account; **critical path**; files: `tests/fixtures/*`). **Status: mostly complete** (rev 2.2 folded its results in). Captured and confirmed: logged-out string, JSON shapes for `vault list`/`item list`/`item totp` (wrappers and flattened TOTP map), real 88-char ids pass the allowlist, single trailing newline on field output, "Field does not exist"/"No TOTP fields found" texts, exact no-lock error, username→email fallback, serial index latency 1.104 s (R3 retired), no personal data in fixtures. **Status: COMPLETE.** All captures done: locked-session (five-line combined stderr), revoked-session (`non-existent session` chain), network-down causal chain, and the update-check question (cannot stall — skipped when stderr is captured). Fixtures at `tests/fixtures/`, identity-free, spot-verified. The disposable CLI session used for capture was revoked afterward.

**T1 — Repo scaffold** ∥. Manifest per §2.2, MIT LICENSE, README stub, executable helper stub emitting a `doctor` envelope, structural `manifest-test.sh` (valid JSON, referenced files exist, no symlinks — deliberately not a validator replica). Accept: `omarchy plugin validate .` passes; `omarchy plugin add "$PWD" --enable` shows the stub icon; hot reload works.

**T2 — Mock harness** ∥ (deps T0). Scenario-driven mock `pass-cli` (`MOCK_SCENARIO`: ready, ready-multivault, empty-vault, zero-vaults, logged-out, locked, no-lock, expired, offline, timeout-sleeps, malformed-json, no-totp, no-username, value-with-trailing-newlines, unicode-titles incl. quotes/newlines/emoji/RTL/shell metacharacters) recording argv to a sandbox log; mock `wl-copy` recording argv + sha256(stdin) only; mock `wl-paste`; `lib.sh`.

**T3 — Helper core** (deps T1, T2). Arg parsing, id/field/bounds validation walls (exit 2 + JSON on violation), JSON emission via jq (never string-built), `doctor`, env sanitization, `timeout` wrapper, stderr classifier per §2.7 (no `Error:`-prefix assumption; case-insensitive). Shellcheck-clean.

**T4 — Helper `index`** (deps T3). Vault iteration, `.items` unwrap, trim-aware exclusion filter (jq-side), merge with vaultName, warnings + partial results, full state classification incl. `cli-missing`. Accept: multi-vault, duplicate/unicode titles, empty vault, zero vaults, partial failure, every auth/network scenario; titles proven absent from argv via calls.log.

**T5 — Helper `copy` + clearer + `lock`** (deps T3; ∥ T4). Sentinel capture (§2.4), username→email fallback (incl. defensive zero-length check), TOTP via flattened-map extraction, `wl-copy --sensitive`(±`-o`), inline subshell clearer with mandatory fd redirection (§3.4), `lock` with `no-lock` classification. Accept: mock wl-copy receives exact bytes incl. trailing-newline-bearing values (hash-verified); response carries no value; `fallbackUsed` correct; no-field paths; clearer clears on match, refuses on mismatch, absent at 0; **helper's copy response returns promptly while the clearer sleeps** (the fd-inheritance hang test).

**T6 — helper-test.sh completion** (deps T4, T5). Full scenario×command matrix, timeout behavior, argv assertions, exit-code discipline (0 handled; 2 bad argv). Deterministic, <60s, green in a bare container.

**T7 — security-test.sh** (deps T5). Static: grep tree for `--show-secrets`, `eval`, `sh -c`, backtick interpolation, `export` of the secret variable, secret-ish QML property names. Dynamic: run copy with a sleeping mock and scan `/proc/*/cmdline` + `/proc/<helper>/environ` for the marker secret; assert marker absent from all outputs and sandbox files. Clearer newer-content test: copy A, clipboard becomes B, clearer fires, B untouched.

**T8 — Service.qml** (deps T3 contracts; ∥ T4–T7). State machine + `refreshing`/`copyBusy`/`staleWarning` per §2.6, generation counter, copy-lifecycle rules (never kill; panel-wide busy; late-response handling), strict response validation + exit-code discipline, four-field model, client-side search, retention rules, `OMARCHY_PROTONPASS_HELPER` override. Lands its Service greps in `source-contract-test.sh` (same PR).

**T9 — Panel.qml** (deps T8). Focus model per §1.1 (search-focused open, intercepted ↑/↓/Enter/Esc, Tab/↓ handoff to list, printable-key refocus), state views per §4 incl. empty-result and stale-warning views, toasts per §1.1(4), `Text.PlainText` everywhere user data renders, terminal launches, bar icon tint mapping per §2.3. Lands its Panel greps in `source-contract-test.sh` (same PR).

**T10 — CI** ∥ (deps T6, T7, T8, T9). GitHub Actions on ubuntu: `bash -n`, shellcheck, manifest/helper/security/source-contract tests. No network, no secrets, no Proton account. A seeded violation must fail the build. (qmllint is best-effort local-only — `qs.Ui` exists only inside omarchy-shell.)

**T11 — Docs + preview** ∥ (deps T9). README (install; plan eligibility incl. the Pass Essentials exclusion and Proton reference links; AUR-namesquat warning, `session create-lock` note, settings table, security model + accepted residual risks, uninstall), preview.png from mock data.

**T12 — Manual acceptance** (release gate; deps all). Checklist on your real account: fresh install → setup → login via panel terminal (web flow + 2FA) → multi-vault index → duplicate titles → all three copy actions incl. email-fallback and no-TOTP items → clipboard-history exclusion (confirm `--sensitive` skip live) → 45s clear → newer-copy survives expiry → paste-once → excludeVaults (incl. names typed with spaces after commas) → lock with and without a configured lock → unlock → network-down states → `omarchy plugin update/disable/remove` → hot reload → shell restart. Divergences feed back into classifier fixtures before tagging.

**T13 — Release** (deps T12). 1.0.0, signed tag, install instructions verified from a clean user.

---

## 6. Verification strategy

- **CI (every PR)**: helper behavioral matrix over mocks+fixtures; structural manifest checks; single source-contract grep suite; security suite (static bans + dynamic `/proc` cmdline/environ scans + clipboard-protection + clearer-hang tests); shellcheck + `bash -n`.
- **Fixtures** are the single source of truth for pass-cli message shapes — source-seeded now, live-confirmed in T0, refreshed in T12; synthetic data only.
- **Local integration**: `omarchy plugin validate .` (the real validator — CI never replicates it), path-install + hot-reload loop, full-UI state walkthroughs with `OMARCHY_PROTONPASS_HELPER` pointed at mocks — no account needed.
- **Release gate**: CI green · validate passes · T12 checklist complete · fixtures match current pass-cli · signed tag.

---

## 7. Delivery sequence

**Critical path**: T0 → T3 → T5 → T7 → T9 → T12 → T13. Parallel lanes after T3: helper (T4–T7) and QML (T8–T9, against frozen §2.5 contracts + mocks); T10/T11 alongside.

| Milestone | Contents | Exit criterion |
|---|---|---|
| M0 Facts | T0–T2 | Fixtures captured; stub installs & hot-reloads |
| M1 Helper | T3–T7 | Full matrix + security suite green |
| M2 UI | T8–T9 | All states walkable, keyboard-complete, on mocks |
| M3 Hardening | T10–T11 | CI gate live; docs done |
| M4 Release | T12–T13 | Real-account acceptance clean; 1.0.0 tagged |

**Risk register**

| # | Risk | Sev | Mitigation |
|---|---|---|---|
| R1 | Classifier misses an undocumented string (network/plan-gate paths) | Med (was High) | Core strings now source-verified; remaining gaps pinned in T0; unknowns fall to safe generic `error`+Retry |
| R2 | pass-cli message/flag churn (fast releases) | Med | Fixture re-runs per release; broad patterns; doctor major-version warning |
| R3 | Index latency (serial per-vault calls + weekly self-update check) | **Retired** | T0 measured 1.104 s serial — well under the 3 s threshold; serial helper stands. Residual: self-update-check stall still to be captured in T0's remainder |
| R4 | Omarchy `qs.Ui` internal API churn (unversioned) | Med | Pin to omarchy-github patterns (first-party-maintained); contract tests catch breakage |
| R5 | `--sensitive` not honored by Omarchy history | Low (was Med) | Skip behavior confirmed in shell source (`capture.sh`); T12 re-confirms live |
| R6 | Ineligible-plan users hit a confusing failure inside the login terminal (invisible to the plugin) | Low | Eligibility notes in setup + LOGGED_OUT views and README (incl. Pass Essentials exclusion); Proton's own terminal error is the authoritative message |
| R7 | Users without a configured session lock confused by Lock action | Low | `no-lock` classification + actionable toast + README note |
| R8 | Co-resident plugins read metadata in the shared shell process | Low (accepted) | Secrets never in QML; metadata-only exposure documented |

**Ready-to-implement checklist** — all resolved: scope frozen · manifest final (validator-tested) · helper CLI + JSON contracts final · state machine + focus model + copy lifecycle final · settings final · clipboard policy (45s hash-verified clear, opt-in paste-once — kept per product decision) · secret-path construction decided (sentinel capture, inline clearer with fd redirect) · retention (session RAM) · login (terminal + web flow) · lock (requires `create-lock`, handled) · TOTP (fail-soft, flattened-map extraction) · vault scoping (all + trimmed exclude string) · username fallback (username→email; empty==absent per source) · identity (`josh2c.protonpass`, MIT) · eligible test account confirmed · **T0 complete — zero remaining unknowns**; every classifier pattern is now live-captured and fixture-pinned. **No blockers.**

---

# v1.1 Refinements Addendum (rev 3.1)

Scope decided after v1.0 field use, a survey of established password quick-access tools across Linux and other platforms. All v1.0 security rules stand unchanged and non-negotiable.

## A1. Scope

**In (core, locked):**
1. **Modifier chords, active even while typing in search**: `Ctrl+U` copy username · `Ctrl+P` copy password · `Ctrl+T` copy TOTP (of the highlighted item) · `Ctrl+R` refresh · `Ctrl+L` lock · `Ctrl+Shift+X` clear clipboard now. `Enter` = copy password, `Shift+Enter` = copy username. Existing plain `u/p/t/L/r` in list focus retained. Rationale: direct mnemonics match our list-focus letters; modifier chords never collide with text entry, a pattern proven across established quick-access tools.
2. **Self-teaching UI**: footer legend showing the live chords (reflecting any remaps); the highlighted row's action buttons show their shortcut labels.
   **(rev 3.1)** Row actions are **icon buttons**, not letter buttons (icon-button convention): Nerd Font glyphs — person for username, key for password, clock for TOTP — sized to the bar's icon conventions. Guardrails (icon-only buttons are an accessibility trap): each button carries an accessible name ("Copy username" / "Copy password" / "Copy TOTP code"), a hover tooltip naming action + shortcut, and the highlighted row still shows the shortcut label beside the icons; the footer legend remains the always-visible text reference. Letters u/p/t stay as list-focus shortcuts — only their button *rendering* changes.
3. **Clipboard countdown + clear-now**: after a copy, the footer shows text-first "Clears in Ns" with a thin progress bar (text-first satisfies reduced-motion); clicking it or `Ctrl+Shift+X` clears immediately — hash-verified, never clearing newer content. Countdown hides on expiry/clear.
4. **Logout**: action beside Lock; **two-step arm/confirm** (button arms to "Confirm log out" for 4 s, then disarms — omarchy-github destructive-action pattern). Runs `pass-cli logout` via the helper; success → LOGGED_OUT, model dropped.
5. **Header status line**: "N logins · synced Xm ago"; during filtering, a match-count badge. Times computed client-side from the last successful index.
6. **Accessibility pass**: keyboard-complete (already), password accessible-role on any element that could name a secret action, countdown announced as text, no motion-only state changes (documented screen-reader failures in comparable tools are the cautionary prior art).

**In (user-selected):**
7. **Recent items before typing**: with an empty query the list shows a "Recent" section (last 8 copied items, most-recent first) above "All". Storage: ids + timestamps **only** — never titles, vault names, or field names — via the helper (§A2), joined against the in-RAM index at render; items no longer in the index are silently dropped. Setting `showRecents` (boolean, default true); disabling also deletes the store.
8. **Remappable keybindings**: setting `keybinds` (string, default "") of comma-separated `chord:action` entries, e.g. `ctrl+shift+c:copy-password,ctrl+o:logout`. Chord grammar: `(ctrl+)?(shift+)?(alt+)?(enter|f[1-9]|[a-z])`, case-insensitive. Actions: `copy-username|copy-password|copy-totp|clear-clipboard|lock|logout|refresh`. Parsed defensively in QML only; an invalid entry is ignored with one console.warn naming the entry (never its position in a secret flow — there is none); valid entries override that chord's default; unlisted defaults remain. The footer legend renders the effective map.

**Explicitly rejected (with reasons, from the same survey):**
- In-panel unlock/master-password entry : credentials in QML violate our §3 model; terminal-only auth stands.
- Username/email row subtitles: usernames never enter QML — unchanged.
- "Open site" action: URLs are not in Proton's non-secret summaries; unavailable without content fetches.
- All-fields enumeration / autotype: content fetch is banned; Wayland autotype is the most complaint-ridden feature in every surveyed tool.
- Favorites section: Proton summary `flags` semantics unverified; revisit if/when documented.

## A2. Contract additions (schemaVersion 1, additive — permitted under the freeze rule)

New helper commands, same envelope (`command` enum grows accordingly):
- `logout` → runs `pass-cli logout`; states `logged-out-ok | cli-missing | unreachable | error` ("already logged out" classifies as `logged-out-ok`).
- `clear-now` → hash-verifies and clears the clipboard; states `cleared | not-owner | error`. Ownership: `copy` now writes the value's sha256 (hash only) to `$XDG_RUNTIME_DIR/omarchy-protonpass.clip` (0600, tmpfs); `clear-now` and the timed clearer both verify the live clipboard against it and delete the file on clear. `not-owner` (mismatch or no file) is a silent no-op for the UI.
- `recents load` → `{"recents": [{"shareId","itemId","ts"}]}` (≤8); `recents note --share-id X --item-id Y` → appends/promotes, prunes to 8, states `ok | error`. File: `$XDG_STATE_HOME/omarchy-protonpass/recents.json` (0600; ids + epoch timestamps only). `copy` calls the note logic internally on success — QML never writes files.

## A3. Tasks (each lands with tests, same discipline as v1.0)

- **T14 — Helper: logout, clear-now, recents, clip-hash file** (bash lane). Mocks gain logout/clear scenarios; security-test extends: recents file contains only id/ts keys; clip file contains only 64-hex; no new env vars; `logout` uses fixed argv. Two-step confirm is QML-side; helper logout is single-shot.
- **T15 — QML: chord table + remap parser** (deps T14 contracts). Default map as §A1.1; `keybinds` parser with the grammar above; unit-style assertions in source-contract tests (parser rejects `ctrl+;`, `meta+x`, duplicate chords keep last).
- **T16 — QML: countdown, clear-now, header status, shortcut labels** (deps T14, T15). Countdown driven by the copy response's `clearSeconds`, client-side timer; clear-now button/chord calls helper `clear-now`; hides on `cleared`/`not-owner`/expiry. Header string + match badge.
- **T17 — QML: recents section** (deps T14). Empty-query view = Recent + All sections; join by ids; respects `showRecents`; disabling triggers store deletion (helper `recents clear` — add to A2 if implemented as a subcommand, else file removal via helper `recents note --clear`; pick one and document in the PR).
- **T18 — Logout UI + accessibility pass** (deps T15). Two-step arm/confirm with 4 s disarm and disarm-on-state-change; accessible roles; reduced-motion audit.
- **T19 — Docs, CI, acceptance, release 1.1.0** (deps all). README chord table + remap syntax + icon legend; **combined acceptance (decided)**: one manual pass covering the full v1.0 T12 checklist plus the v1.1 additions — chords while typing, remap round-trip, countdown/clear-now, logout confirm + re-login, recents privacy check (`recents.json` contains no strings besides ids), recents off deletes store, icon buttons expose accessible names (Orca spot check) — then a single signed `1.1.0` tag; no separate 1.0.0.

Parallel: T14 alone first (contracts), then T15–T18 in parallel, T19 last. Settings schema additions: `showRecents` (boolean, true), `keybinds` (string, ""), both non-secret.

## A4. Security notes for v1.1

Unchanged: secrets/usernames never in QML; argv/env/log rules; terminal-only auth. New surfaces: (1) recents file — ids+timestamps only, 0600, deleted on opt-out; ids are opaque but treat the file as metadata-at-rest and say so in README. (2) clip-hash file — hash only, tmpfs, deleted on clear; a hash of a weak password is offline-attackable in principle, which is why it never leaves the runtime dir and never enters QML. (3) logout is destructive (full re-login) — two-step confirm, and the arm state disarms on any state change. (4) Remap parser accepts no shell-bound strings — chords/actions are enum-validated tokens consumed only by QML.

---

# v1.2 Refinements Addendum (rev 4.1)

Field-feedback pass. All v1.0/v1.1 security rules stand; usernames remain hidden (decided — rows stay identifier-free; vault name disambiguates).

## B1. Scope (decided)

1. **Plain click-to-copy icons**: remove hover tooltips, per-row shortcut labels, and the footer key legend — all shortcut UI goes. Icons are simply click-to-copy. Chords keep working (README becomes their sole documentation). `Accessible.name` annotations stay — they are screen-reader metadata, not visible chrome.
2. **Row subtitles**: "used <relative> ago" from the local recents timestamps; items never copied show "created <date>" from the summary's `create_time`. All data already on hand; nothing new stored. Relative times computed client-side; no per-second timers (refresh on model change/panel open). Date-group section headers: deferred (Recent/All sectioning already exists).
3. **New login creation** — two flows, invariant intact (panel never holds a secret):
   - **(rev 4.1)** T20 verification found pass-cli 2.3.2 cannot combine `--from-template -` with `--generate-password` (template path returns first, `login.rs:163`; generation lives only on the argv path, which requires `--title` in argv — banned by §3.6), and there is **no interactive create flow** (PTY-verified: immediate exit 1). Amended design:
   - **Generated (sole flow, in-panel)**: form with title, username or email, vault picker → helper `create` **generates the password itself** (crypto-quality: `/dev/urandom`, 24 chars, mixed classes), embeds it in the stdin template JSON, pipes to `pass-cli item create login --from-template -`, and wipes the variable. Exposure class is identical to the existing copy path (transient unexported helper memory + pipe — the accepted class); still never argv/QML/env/files/logs. Success toast offers "Copy password" via the normal copy path (source of truth: the vault).
   - **Custom password: cut.** Without an interactive create, a terminal flow would force `--password` into a typed shell command (history + world-readable argv) — worse than not shipping. README directs custom-password creation to the official Proton apps.
4. **Explicitly rejected**: typed password field in the panel (breaks secrets-never-in-QML; same class as the rejected in-panel unlock); password reveal/masked display; username subtitles.

## B2. Contract addition (schemaVersion 1, additive)

- `create --share-id <id>` reading a JSON body from **stdin**: `{"title": "...", "username": "..."}` or `{"title": "...", "email": "..."}` (exactly one of username/email; both ≤ 500 chars; title required non-empty; unknown keys rejected). **(rev 4.1)** The helper generates the password internally (`/dev/urandom`, 24 chars, upper/lower/digit/symbol guaranteed), fills the captured template shape `{"title","username","email","password","totp_uri":null,"urls":[]}`, and pipes it to `pass-cli item create login --share-id <id> --from-template -`; the password variable is wiped after the pipe closes. Title/username/password never touch argv (§3.6 applies to creation identically). States: `created` (extends: `"itemId","shareId"` if pass-cli reports them, else re-indexed) `| invalid-input |` shared error states. On success the helper appends the new item to recents.

## B3. Tasks

- **T20 — Helper `create` + CLI verification** (bash lane): `--get-template` shape captured to fixtures; stdin-JSON validation walls (strict keys, lengths, reject unknown fields); mock scenarios (created, invalid-input, auth states); security tests extend: title/username absent from argv (calls.log), no password material anywhere, template stdin not logged. Also pin the interactive-terminal create behavior (B1.3).
- **T21 — QML: remove shortcut chrome** (small): tooltips, row labels, footer legend deleted; Accessible.name retained; source-contract greps updated (assert legend absent, Accessible.name present).
- **T22 — QML: subtitles** (deps none): recents-ts join → "used X ago", fallback "created <date>"; locale-safe formatting; PlainText.
- **T23 — QML: create form** (deps T20): non-secret fields only; vault picker fed from index vault names; validation mirrors helper walls; generated-flow success → toast + copy-password affordance; terminal button for custom flow; disabled while `copyBusy`/create in flight.
- **T24 — Docs, combined acceptance, release**: README (create flows, chord table as sole shortcut reference); acceptance additions (create-generated round-trip incl. copy of new password, terminal custom create, subtitle correctness, no shortcut chrome, chords still fire); **release decision: the pending v1.1 tag is superseded — one combined acceptance covers v1.0+v1.1+v1.2, single signed `1.2.0` tag.**

Order: T20 first (contract), T21/T22 parallel anytime, T23 after T20, T24 last. T19 (in flight) narrows to docs + CI timeouts; its release step moves to T24.

## B4. Security notes

Create introduces the first **write** path. Mitigations: stdin-only fields (no argv), strict input walls both sides, helper-side generation with immediate variable wipe (same transient class as the copy path — rev 4.1), no user-chosen secrets anywhere in our surfaces, and the panel form holds only non-secret fields. No new files, env vars, or retention. Abuse surface (a malicious co-resident plugin invoking create) is unchanged in kind from existing copy/lock — same-UID actors already hold full CLI access; documented in README's residual risks.
