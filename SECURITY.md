# Security

This plugin copies passwords and two-factor codes. You are right to be careful about what you install for that. This document states plainly what the plugin can and cannot do, and, more importantly, how to check every claim yourself in about a minute. Nothing here asks you to take our word for it.

## Security at a glance

- **It makes no network connections of its own.** Only Proton's official `pass-cli` talks to Proton's servers. The plugin never opens a socket, never calls out, never "phones home."
- **It never sees your Proton password.** Signing in opens Proton's own `pass-cli` in a terminal. Your password and any 2FA go straight to Proton; the plugin only checks afterward that a session exists.
- **It never shows or stores a secret.** Field values go from `pass-cli` straight to your clipboard, marked sensitive. They never appear in the panel, never touch a log, never land in a file.
- **The only things it writes to disk** are a list of recently used item IDs (no names, no secrets) and a one-way hash of the last value it copied (used to auto-clear the clipboard safely). Both are yours-only files, and the recents list is deleted the moment you turn the setting off.

## Verify it yourself

The entire runtime is four files (one Bash helper, two QML files, one small JavaScript file), about 3,500 lines you can read. Run these from the plugin directory:

```sh
# No network code. This returns nothing at all.
grep -rnE 'curl|wget|http|nc |socket|XMLHttpRequest' *.qml Keybinds.js omarchy-protonpass

# Secrets are never revealed: the only hits for --show-secrets are this
# document and the test that FORBIDS it.
grep -rn 'show-secrets' .

# Every clipboard copy is marked sensitive so Omarchy's clipboard history skips it.
# The copy at the bottom passes copy_args, declared as (--sensitive) above it.
grep -nE 'wl-copy|--sensitive' omarchy-protonpass

# Sign-in is delegated to the official CLI in a terminal, the plugin never handles it.
grep -n 'pass-cli.*login' Panel.qml

# No arbitrary-code constructs in the helper or the keybind parser.
grep -nE 'eval|sh -c|`' omarchy-protonpass Keybinds.js
```

And the strongest check is mechanical: `tests/security-test.sh` runs on every commit in CI (offline, with no Proton account). It statically forbids `--show-secrets`, `eval`, `sh -c`, exported secret variables, and secret-shaped UI properties, and it dynamically plants a marker "secret," runs a real copy, and scans process arguments, the environment, and every file the run touched to prove the marker never escaped. You can run it yourself: `bash tests/security-test.sh`.

## Scope and limits

What this document defends, and what it does not.

**Assets.** Your field values (passwords, usernames, TOTP codes); your Proton
session; the clipboard; and the availability of the Omarchy shell process the
panel runs inside.

**Adversaries.** A local unprivileged process on your machine reading arguments,
environment, or files. An editor of a vault you have accepted a share of, who
authors the item metadata this plugin reads. Anyone who can read your clipboard
history.

**Explicitly out of scope.** A compromised Proton account or `pass-cli` binary;
a compromised Omarchy shell; a privileged local attacker who can read another
process's memory; and physical access to an unlocked session. Nothing here
defends against those, and no plugin can.

**A note on shared vaults.** `pass-cli` is a trusted channel, but item titles and
vault names inside a shared vault are authored by whoever can edit it. The index
path therefore treats that metadata as untrusted input: title and vault-name
length, vault count, item count, response size, and total indexing time are all
bounded. `tests/budget-test.sh` enforces every one of those bounds against a
hostile CLI, and CI fails the build if a bound is raised past a sane ceiling.
When a limit is reached the panel says so; it never silently drops logins.

## How copying a secret actually works

1. You pick an item and an action. The panel sends the helper only an **opaque item ID** and a **field name** (`username` / `password` / `totp`), never a value.
2. The helper asks `pass-cli` for that one field. The value arrives on a pipe and lives in a single shell variable that is never exported and is erased right after use.
3. The value is piped to `wl-copy --sensitive`. Omarchy's clipboard history skips anything marked sensitive, so it does not persist there.
4. After the configured delay, the clipboard is cleared, but **only if it still holds exactly the value we put there.** If you copied something else in the meantime, your newer content is left untouched.

The value never crosses into the panel/UI layer. The panel only ever handles non-secret metadata: item titles, vault names, and which field you asked for.

## What it deliberately never does

- Never runs with, stores, or transmits your Proton password, sign-in and unlock happen only in the official CLI, in a terminal you control.
- Never uses `pass-cli --show-secrets`.
- Never displays a password, TOTP code, or username on screen.
- Never writes a secret value to any file, log, notification, or command line.
- Never bundles, patches, or installs Proton software, it points you at the official installer and gets out of the way.

## Honest limits

No security tool should overclaim, so here is what this plugin **cannot** protect against, by design:

- **Anything already running as your user.** A program running under your account can already read your `pass-cli` session, your process memory, and your live clipboard. This plugin operates inside that boundary and does not claim to defend it. If your account is compromised, so is your vault, with or without this plugin.
- **The clipboard while a value is live.** On Wayland, any client of your compositor can read the clipboard while a value sits there. Marking it sensitive keeps it out of clipboard *history*, and the auto-clear shortens the window, but during that window the value is readable by same-user software. Use the shortest clear time you're comfortable with, or clear it manually.
- **The one-way hash at rest.** To auto-clear safely, the helper keeps a SHA-256 hash of the last copied value in a user-only runtime file. A hash cannot be reversed, but a *low-entropy* value (like a 6-digit TOTP) could be guessed offline from it. That again takes an attacker already on your user account, who could read the live clipboard anyway. Strong generated passwords are unaffected.
- **Offline access.** Proton enforces session state server-side, so listing and copying require a network connection every time.

## Reporting a vulnerability

If you find a security issue, please report it privately: open a GitHub security advisory on this repository, or email the maintainer at the address in the commit history, rather than filing a public issue. We'll acknowledge and respond.
