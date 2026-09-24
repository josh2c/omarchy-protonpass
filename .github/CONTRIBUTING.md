# Contributing

Thank you for looking at this plugin closely. It copies passwords, so every
change is reviewed as a trust decision. Here is what to expect.

## Before you open a pull request

- Check the README's out-of-scope list. Editing, deleting, sharing,
  attachments, custom-password creation, secret display, and offline use are
  deliberate omissions, not gaps.
- Keep secrets out of the QML layer, out of process arguments, out of the
  environment, and off disk. Redundant hygiene in the helper is deliberate;
  please do not remove a check because another check already covers it.
- Run ShellCheck and the offline suites: `tests/manifest-test.sh`,
  `tests/helper-test.sh`, `tests/security-test.sh`,
  `tests/source-contract-test.sh`, `tests/budget-test.sh`.
- The QML harnesses need Quickshell and a nested compositor. If you cannot run
  them, say so; we run them before merge.
- Write commit messages in plain prose: an imperative title, then what changed
  and why. Do not add tool attributions or session links to commits or the PR
  body; changes are squashed with a rewritten message if they carry any, with
  you as the author.

## What review looks like

1. Intake: scope, the security leave-alone areas, and commit hygiene.
2. Independent review: the code is read against the tree, and every new test
   is checked by reverting the fix to see it fail.
3. Red team by asset: secret values, the Proton session, the clipboard, the
   shell's availability, the helper path, and anything written to disk. If
   your change adds untrusted input, say how its type, size, count, and rate
   are bounded.
4. Merge into a batched release, then marketplace verification of the new
   commit.

Security issues go to a private advisory or the maintainer's email, not a
public issue. See SECURITY.md.
