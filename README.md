# Proton Pass for Omarchy

A native Omarchy Quattro bar widget for keyboard-first Proton Pass login search and safe Wayland clipboard copy through Proton's official [`pass-cli`](https://protonpass.github.io/pass-cli/).

![Proton Pass quick-access panel](preview.png)

This plugin complements the official Proton Pass apps and CLI. It does not bundle, patch, or install Proton software, and it never displays a username, password, or TOTP code.

> [!IMPORTANT]
> Proton Pass CLI access requires a personal **Pass Plus** plan (or a bundle that includes it) or a business **Pass Professional** plan. Business **Pass Essentials is not eligible**. See Proton's [personal plan guide](https://proton.me/support/proton-pass-plans-explained) and [business plan comparison](https://proton.me/business/pass/pricing).

## Features

- Search active login items across all non-excluded vaults by title or vault name.
- Copy usernames, passwords, and TOTP codes without sending secret values through QML.
- Fall back from a missing username to the login's email address.
- Mark every clipboard offer sensitive and clear it after a configurable delay only if it still contains the copied value.
- Optionally make clipboard offers paste-once.
- Sign in and unlock through Proton's normal CLI flow in a terminal; credentials remain under Proton's control.
- Keep only item IDs, share IDs, titles, and vault names in memory for the current shell session.

Item editing, creation, deletion, sharing, attachments, password generation, secret display, and offline use are outside the v1 scope.

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

## Keyboard use

The panel opens with search focused.

| Key | Action |
|---|---|
| Type | Filter by login title or vault name |
| `Down` or `Tab` | Enter list navigation |
| `j` / `k` or `Down` / `Up` | Move through results |
| `Enter` or `p` | Copy password |
| `u` | Copy username, falling back to email |
| `t` | Copy TOTP |
| `L` | Lock the Proton Pass CLI session |
| `r` | Refresh the index |
| `/` or another printable key | Return to search; `/` itself is not inserted |
| `Esc` | Clear search, then close the panel |

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

Vault names containing commas cannot be excluded individually in v1.

## Security model

QML receives only non-secret item metadata. Copy requests send validated opaque IDs and a fixed field enum to the bundled Bash helper. The helper is the only plugin component that handles secret bytes: it retrieves one field into an unexported variable, pipes the value directly to `wl-copy --sensitive`, hashes it, unsets it, and returns secret-free JSON.

Secrets are never placed in:

- QML properties or rendered UI
- command-line arguments or exported environment variables
- files, logs, notifications, or helper JSON
- clipboard-history entries created by Omarchy's built-in history capture

Automatic expiry is hash-verified. When the timer fires, the helper clears the clipboard only if its current content still matches the value this plugin copied. Content copied afterward is left untouched.

### Accepted residual risks

- Any Wayland client able to read the clipboard can access a copied value while it remains live. The sensitive marker and expiry window reduce exposure; they do not isolate the clipboard.
- An attacker already running as your user can access the Proton CLI session and same-user process memory. The helper's transient shell variable and pipe buffers are inside that already-compromised boundary.
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

See [`PLAN.md`](PLAN.md) for the audited implementation and release checklist.

## License

MIT
