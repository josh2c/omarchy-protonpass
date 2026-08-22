# Committed baselines

Reference dumps of the QML layer as it behaves in this release. They exist so a
future change can be diffed against something instead of asserted about.

| File | Produced by | What it pins |
|---|---|---|
| `panel-snapshot.txt` | `tests/qml-panel-snapshot.sh` | Every visible item in sixteen panel states: absolute position, size, text, glyph, colour, font, alignment, wrap, accessible name |
| `key-matrix.txt` | `tests/qml-key-matrix.sh` | Every keyboard binding in both focus contexts, and what the panel did |
| `service-scenarios.txt` | `tests/qml-service-scenarios.sh` | The state the Service settles in for each mock scenario, plus the auth-during-refresh invariant |

`tests/qml-panel-pixel-check.sh` produces no baseline. It screenshots one state
next to its dump, and exists for when a dump and your expectation disagree: it
shares no logic with the harness, so it can arbitrate.

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
- `panel-snapshot.txt` is captured at the default 1200x900. Presentational
  changes are accepted at two viewport sizes -- rerun with
  `NESTED_MONITOR=1920x1200` for the second -- because a layout fault that only
  shows when the panel has less room is invisible on a large display.
- The snapshot harness **fails loudly rather than emitting a doubtful dump**. It
  rejects a tree whose geometry is internally impossible (two differently sized
  children of a Row sharing an x, a Column's children sharing a y), because that
  is a position read against a parent chain still mid-polish, not a render. If a
  run fails with "panel did not render", rerun it; if it fails repeatedly,
  something is genuinely wrong.

Refresh a baseline only when a change is *meant* to alter what it records, and
say so in the pull request that does it.
