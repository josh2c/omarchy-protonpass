# Proton Pass for Omarchy

A native Omarchy Quattro bar widget for keyboard-first Proton Pass login search and safe clipboard copy through Proton's official `pass-cli`.

This repository is under active development. The current scaffold is not yet ready for normal installation or secret handling.

## Planned requirements

- Omarchy Quattro (4.x)
- Proton Pass CLI 2.3 or newer
- A Proton plan with CLI access: personal Pass Plus (or a bundle that includes it) or business Pass Professional
- `wl-clipboard`, `jq`, `bash`, and `coreutils`

Business Pass Essentials does not include CLI access.

## Security boundary

The finished plugin will keep usernames, passwords, TOTP codes, and all other item content out of QML, command arguments, logs, files, notifications, and JSON responses. Secret values will exist only transiently inside the helper while being offered to the Wayland clipboard.

## Status

Implementation follows [`PLAN.md`](PLAN.md). T0 is complete; T1 provides the installable repository scaffold.

## License

MIT
