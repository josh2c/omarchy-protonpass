# omarchy-protonpass — development documents

This is an orphan branch. It shares no history with `main` and contains no
plugin code. It holds the development process documents that used to sit in the
repository root, where `omarchy plugin add` copied them into every user's
config directory.

- [`PLAN.md`](PLAN.md) — the v1 implementation plan: product, architecture,
  security, and scope decisions, with the audit log of every revision.
- [`T12-ACCEPTANCE.md`](T12-ACCEPTANCE.md) — the combined v1.0 + v1.1 + v1.2
  manual acceptance checklist, run against a real account before signing a tag.

Both files were on `main` through `dba51c8`; their history is still there.

`PLAN.md` is no longer used as a changelog. Release notes go in the annotated
release tags.
