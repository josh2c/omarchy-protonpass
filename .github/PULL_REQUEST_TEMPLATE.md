## What changed and why

## New surface

State "none" if the change adds no input, file, process, or command. Otherwise:
what new input, file, process, or command exists after this change, and how
its type, size, count, and rate stay bounded.

## Tests

Which suites ran and passed. For each new test, confirm it fails with the fix
reverted. If the QML harnesses were not run, say so.

## Checklist

- [ ] ShellCheck clean
- [ ] Offline suites green (manifest, helper, security, source-contract, budget)
- [ ] No secrets in QML, argv, environment, or files
- [ ] No tool attributions or session links in commits or this description
