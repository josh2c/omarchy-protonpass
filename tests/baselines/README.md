# Committed baselines

Reference dumps of the QML layer as it behaves in this release. They exist so a
future change can be diffed against something instead of asserted about.

| File | Produced by | What it pins |
|---|---|---|
| `panel-snapshot.txt` | `tests/qml-panel-snapshot.sh` | Every visible item in fifteen panel states: absolute position, size, text, glyph, colour, font, alignment, wrap, accessible name |
| `key-matrix.txt` | `tests/qml-key-matrix.sh` | Every keyboard binding in both focus contexts, and what the panel did |
| `service-scenarios.txt` | `tests/qml-service-scenarios.sh` | The state the Service settles in for each mock scenario, plus the auth-during-refresh invariant |

Workflow:

```
tests/qml-panel-snapshot.sh /tmp/after.txt
diff tests/baselines/panel-snapshot.txt /tmp/after.txt
```

These are **not** pass/fail tests and are deliberately not wired into CI.

- `panel-snapshot.txt` records this machine's font metrics. Geometry will differ
  on a host with different fonts, so compare runs from one machine.
- `panel-snapshot.txt` and `key-matrix.txt` need a live Wayland session; the key
  matrix also needs `wtype` and `Hyprland` (it runs its own nested compositor so
  the synthetic keystrokes cannot reach your session).
- `service-scenarios.txt` is headless.

Refresh a baseline only when a change is *meant* to alter what it records, and
say so in the pull request that does it.
