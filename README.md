# Proton Pass for Omarchy

A native Omarchy Quattro bar widget for keyboard-first Proton Pass login search and safe Wayland clipboard copy through Proton's official [`pass-cli`](https://protonpass.github.io/pass-cli/).

![Proton Pass quick-access panel](preview.png)

This plugin complements the official Proton Pass apps and CLI. It does not bundle, patch, or install Proton software, and it never displays a retrieved username, password, or TOTP code.

> [!IMPORTANT]
> Proton Pass CLI access requires a personal **Pass Plus** plan (or a bundle that includes it) or a business **Pass Professional** plan. Business **Pass Essentials is not eligible**. See Proton's [personal plan guide](https://proton.me/support/proton-pass-plans-explained) and [business plan comparison](https://proton.me/business/pass/pricing).

## Features

- Search active login items across all non-excluded vaults by title or vault name.
- Keep refresh, new-login, lock, and logout controls fixed in the header while long login lists scroll independently.
- Copy usernames, passwords, and TOTP codes without sending secret values through QML.
- Fall back from a missing username to the login's email address.
- Create a login with a generated password from non-secret title, username or email, and vault fields.
- Mark every clipboard offer sensitive and clear it after a configurable delay only if it still contains the copied value.
- Clear the current plugin-owned clipboard value immediately from the panel or keyboard.
- Optionally make clipboard offers paste-once.
- Show recently copied logins using an optional local ID-and-timestamp-only history.
- Show when a login was last used, or when it was created if it has not been copied recently.
- Lock or log out of the CLI session; logout requires a second confirmation.
- Sign in and unlock through Proton's normal CLI flow in a terminal; credentials remain under Proton's control.
- Keep only item IDs, share IDs, titles, vault names, creation times, and recent-use timestamps in memory for the current shell session.

Item editing, deletion, sharing, attachments, custom-password creation, secret display, and offline use are outside the current scope.

## Requirements

- Omarchy Quattro (4.x)
- Proton Pass CLI 2.3 or newer on `PATH`
- An eligible Proton plan as described above
- `wl-clipboard`
- Network access for every refresh and copy
- `jq`, `bash`, and GNU coreutils, which are included with Omarchy

## Install

1. Install Proton's official CLI if needed:

   ```bash
   curl -fsSL https://proton.me/download/pass-cli/install.sh | bash
   ```

   On Arch, the community package is `proton-pass-cli-bin`:

   ```bash
   yay -S proton-pass-cli-bin
   ```

   > [!WARNING]
   > The AUR package named `pass-cli` is an unrelated project. Do not install it for this plugin.

2. Install the Wayland clipboard tools:

   ```bash
   sudo pacman -S wl-clipboard
   ```

3. Add and enable the plugin:

   ```bash
   omarchy plugin add https://github.com/josh2c/omarchy-protonpass.git --enable
   ```

4. Open the key icon in the bar. If you are signed out, choose **Sign in**. The plugin launches plain `pass-cli login` in a terminal, which uses Proton's browser authentication flow.

The panel automatically rechecks the session when it is opened again after login or unlock.

## Create a login

Choose the **Create login** action, enter a title and either a username or email, then select any available non-excluded vault. Empty vaults remain available in the picker. The plugin helper generates a cryptographically random 24-character password with upper-case, lower-case, numeric, and symbol characters and sends the complete login template to `pass-cli` over standard input. The password never enters QML, command-line arguments, the environment, logs, or files.

After creation, use **Copy password** in the success message to retrieve the new password through the normal sensitive clipboard path. Proton Pass remains the source of truth; the plugin does not retain the generated password.

To create a login with your own password, use an official Proton Pass app. The CLI has no safe interactive create flow, and putting a custom password in a shell command would expose it through shell history and process arguments.

## Keyboard use

The panel opens with search focused. Row buttons intentionally contain no visible shortcut labels or hover shortcut hints; this section is the sole shortcut reference.

### Global chords

These work while typing in search and while navigating the list.

| Chord | Action |
|---|---|
| `Enter` | Copy password |
| `Shift+Enter` | Copy username, falling back to email |
| `Ctrl+U` | Copy username, falling back to email |
| `Ctrl+P` | Copy password |
| `Ctrl+T` | Copy TOTP |
| `Ctrl+R` | Refresh the index |
| `Ctrl+L` | Lock the Proton Pass CLI session |
| `Ctrl+Shift+X` | Clear the plugin-owned clipboard value now |

### List and search keys

| Key | Context and action |
|---|---|
| Type | In search: filter by login title or vault name |
| `Down` or `Tab` | From search: enter list navigation |
| `j` / `k` or `Down` / `Up` | In list focus: move through results |
| `p` | In list focus: copy password |
| `u` | In list focus: copy username, falling back to email |
| `t` | In list focus: copy TOTP |
| `L` | In list focus: lock the Proton Pass CLI session |
| `r` | In list focus: refresh the index |
| `/` or another printable key | From list focus: return to search; `/` itself is not inserted |
| `Esc` | Clear search, then close the panel |

Modifier chords can be remapped with the **Keyboard shortcuts** setting. Enter comma-separated `chord:action` pairs, for example:

```text
ctrl+shift+c:copy-password,ctrl+o:logout
```

Chord grammar is `(ctrl+)?(shift+)?(alt+)?(enter|f[1-9]|[a-z])`, case-insensitive. Actions are `copy-username`, `copy-password`, `copy-totp`, `clear-clipboard`, `lock`, `logout`, and `refresh`. Invalid entries are ignored. A remapped logout chord still uses the panel's two-step confirmation.

Mouse users can select a row and use its explicit username, password, or TOTP action. Selection alone never copies anything.

### Session locking

`pass-cli session lock` works only after a session lock has been configured. Run this once in a terminal if you want the panel's `L` action:

```bash
pass-cli session create-lock
```

The unlock button launches `pass-cli session unlock` in a terminal so the CLI handles the lock credential directly.

## Settings

Configure the widget through Omarchy's plugin settings.

| Setting | Default | Range / behavior |
|---|---:|---|
| Clear clipboard after | 45 seconds | 0–300 seconds; `0` disables automatic clearing |
| Paste once | Off | Offers the value once with `wl-copy -o`; some browsers and Electron apps read more than once and may fail to paste |
| Excluded vaults | Empty | Comma-separated, case-sensitive exact vault names; surrounding spaces are trimmed |
| Keyboard shortcuts | Empty | Comma-separated `chord:action` overrides; unmodified defaults remain active |
| Show recent items | On | Shows up to eight recently copied logins; turning it off deletes the local recents store immediately |

Vault names containing commas cannot be excluded individually in v1.

## Security model

QML receives only non-secret item metadata from Proton. Copy requests send validated opaque IDs and a fixed field enum to the bundled Bash helper. The helper is the only plugin component that handles secret bytes: it retrieves one field into an unexported variable, pipes the value directly to `wl-copy --sensitive`, hashes it, unsets it, and returns secret-free JSON.

Login creation sends the user-entered, non-secret title and username or email to the helper as a strict JSON document over standard input. The helper generates the password from `/dev/urandom`, sends it inside the stdin template consumed by `pass-cli`, and wipes its transient variable after the pipe closes. There is no custom-password field or terminal command path.

Secrets are never placed in:

- QML properties or rendered UI
- command-line arguments or exported environment variables
- files, logs, notifications, or helper JSON
- clipboard-history entries created by Omarchy's built-in history capture

Automatic expiry is hash-verified. When the timer fires, the helper clears the clipboard only if its current content still matches the value this plugin copied. Content copied afterward is left untouched.

When **Show recent items** is enabled, the helper stores at most eight `{shareId, itemId, ts}` records in `$XDG_STATE_HOME/omarchy-protonpass/recents.json` (normally `~/.local/state/omarchy-protonpass/recents.json`) with mode `0600`. It stores no titles, vault names, usernames, fields, or secret values. The panel joins those opaque IDs against its in-memory index. Turning the setting off deletes the store immediately.

### Accepted residual risks

- Any Wayland client able to read the clipboard can access a copied value while it remains live. The sensitive marker and expiry window reduce exposure; they do not isolate the clipboard.
- An attacker already running as your user can access the Proton CLI session and same-user process memory. The helper's transient shell variable and pipe buffers are inside that already-compromised boundary.
- A co-resident same-user plugin can invoke the helper's copy, create, lock, or logout operations; same-UID code already has direct access to the Proton CLI session.
- The clipboard ownership file contains only a password hash and lives in `$XDG_RUNTIME_DIR`, but a weak password hash is theoretically susceptible to offline guessing while that runtime file exists.
- The recents file is non-secret metadata at rest. It contains opaque item/share IDs and timestamps only and is deleted when recents are disabled.
- Proton Pass CLI sessions are online: refresh, copy, lock, and unlock behavior depends on Proton being reachable.

## Update or uninstall

Review and apply plugin updates with:

```bash
omarchy plugin update josh2c.protonpass
```

Disable the widget without removing its checkout:

```bash
omarchy plugin disable josh2c.protonpass
```

Remove it completely:

```bash
omarchy plugin remove josh2c.protonpass
```

Removing this plugin does not uninstall Proton Pass CLI or alter Proton's session files.

## Development

The test suite uses captured, identity-free CLI fixtures and mocks; CI needs no Proton account or network access.

```bash
tests/helper-test.sh
tests/security-test.sh
tests/manifest-test.sh
tests/source-contract-test.sh
omarchy plugin validate .
```

See [`PLAN.md`](PLAN.md) for the audited implementation and the [combined 1.2.0 acceptance checklist](T12-ACCEPTANCE.md) for the release gate.

## License

MIT
