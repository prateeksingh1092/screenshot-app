# 77: Adapters as a package product

**What to build:** The app links `FrisketAdapters` as a package product instead of compiling the adapter sources itself, so every line the app runs is compiled once and tested. Preference keys live in one enum, without the never-released ⌃⌥⌘ migration. Unneeded `@preconcurrency` imports, `Sendable` on actor-confined types, and force unwraps in History are removed.

**Blocked by:** 74, 75, 76

**Phase:** 4 (O13 step 2)

**Status:** ready-for-agent

- [ ] The app target compiles no adapter source file.
- [ ] The unsigned build, the suite and `ci.sh` are green.
- [ ] The force unwraps in History are replaced by typed failures.

## Comments

### 2026-09-24: coordinator, created

Created by to-tickets from `Plans/dreamy-giggling-barto.md` and spec stories 82–101 (decision 58). Claude Opus 5.5, Claude Code, medium effort.
