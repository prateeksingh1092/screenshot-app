# Ticket 40 code review

Fixed point: `5c095bf` (merge-base with main). Review after the implementer
snapshot on `ticket/40-final-acceptance`.
Model: Cursor coordinator chat (Claude Opus 5.5 High).

## Standards

- Development stays native `x86_64` / `.frisket.debug`.
- Release is a separate configuration, not a mutation of Development.
- The C3 label refuses install and launch (judgement: `--sign` is optional
  after Xcode's per-target codesign hung).

## Spec

- Universal Release exists in the project and compiled on this host
  (`lipo`: `x86_64 arm64`, production identifier).
- The signed C3 label was not produced: `codesign` timed out on the keychain.
  That is an environment gate, not a missing project setting.
- Manual checklist, ratified targets, and Codex assessment remain open.
  Not a v1 declaration.

## Summary

Standards: 0 hard findings. Spec: 1 open gate (signed label needs a keychain
unlock). Worst per axis: unattended signing of the new production bundle ID.
