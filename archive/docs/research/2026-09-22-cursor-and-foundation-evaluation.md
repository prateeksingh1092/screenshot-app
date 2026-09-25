# Cursor setup and Snapzy evaluation status

Date: 2026-09-22. This records completed checks and outstanding evidence, not foundation acceptance.

Subsequent tooling review: Cursor Opus 5.5 High completed its independent assessment, and Codex verified a native-framework CLT compile/link/run. Full Xcode is required by Snapzy’s existing source workflow, not by all native macOS development. See the [verified assessment and limitations](2026-09-22-xcode-necessity-assessment.md). Setup-only observations below retain their original scope.

## Outcome

Cursor desktop is installed and the screenshot-app folder is open. Codex remains the lead agent; the user's existing Cursor Ultra plan may provide complementary models and IDE capabilities. All project AI work must stay within existing ChatGPT/Cursor Ultra allowances, with no API-key billing or paid overages.

Independent stack research favors **Swift + AppKit/SwiftUI + ScreenCaptureKit + Vision + SQLite/GRDB** for the accepted macOS-only workflow. This is a reasoned fit assessment, not a performance benchmark. See the [full comparison](2026-09-22-stack-independent-assessment.md) for SwiftUI-heavy, Tauri/Rust, Electron/TypeScript, Qt/C++, and persistence tradeoffs.

## Actual local checks

| Check | Evidence/result |
|---|---|
| Machine | `uname -m`: x86_64; `sw_vers`: macOS 26.7, build 25G229. |
| Cursor CLI | Explicit executable at `~/.local/bin/cursor-agent`; version 2026.09.18-9a7762b; browser sign-in completed. Bare `agent` resolves to Grok. No project analysis was run through Cursor CLI during this setup. |
| Cursor desktop | Official download page's Intel 3.21 channel installed version 3.21.18 at `~/Applications/Cursor.app`; executable is x86_64. |
| Cursor integrity | Read-only installer mounted; macOS signature verification passed outside the sandbox; Gatekeeper returned `accepted`, `source=Notarized Developer ID`. Installed copy passed those checks too. No Gatekeeper bypass or ad-hoc re-signing. |
| IDE workspace | Cursor `--status` reported the running desktop and `Folder (screenshot-app)`. |
| Codex | CLI 0.156.0; `codex login status`: logged in using ChatGPT. Official `openai.chatgpt` extension 26.908.40401 installed in Cursor. |
| Pocock skills | 25 existing local engineering/productivity skills copied from version 1.2.3 into `.cursor/skills/matt-pocock/`, including references, upstream license, and hash provenance. UI skill-picker discovery has not been visually checked. |
| Snapzy release | Downloaded official v1.32.3 DMG; SHA-256 matches GitHub release metadata: `0fd1f52d92df0bc8118f08d080ba6bf22047c10faac9a48aa5a174835321dadb`. |
| Snapzy architecture | Actual release executable contains both x86_64 and arm64 slices. This resolves the earlier unverified Intel-binary question for this release. |
| Snapzy integrity | Signature verification passed; Gatekeeper returned `accepted`, `source=Notarized Developer ID`. Binary was inspected read-only, not installed or launched. |
| Source build | Not attempted: full Xcode is absent from `/Applications` and `~/Applications`; selected developer directory is Command Line Tools; `xcodebuild -version` fails for lack of full Xcode. This is an environment blocker, not a Snapzy build failure. |

Sources for downloads: [Cursor official downloads](https://cursor.com/download), [Snapzy v1.32.3 release](https://github.com/duongductrong/Snapzy/releases/tag/v1.32.3). Binary results above are direct local observations, not marketing claims.

## IDE versus terminal

The user explicitly chose Cursor as the IDE. For that purpose the desktop app is appropriate: it offers a persistent editing and review environment, while the CLI is useful for scripted, bounded agent tasks. This is a workflow judgment, not a claim that the desktop model reasons better. Cursor documents interactive, Ask/Plan, and headless CLI workflows; these complement an editor. [CLI documentation](https://cursor.com/docs/cli/overview), [headless operation](https://cursor.com/docs/cli/headless)

Native Swift still needs Apple's build tools. Swift.org lists Cursor as a Swift-capable editor through its Swift extension; Cursor documents Xcode integration, with Xcode handling compilation, testing, and previews. No Xcode MCP bridge or Swift debugging setup has been configured yet. [Swift tools](https://www.swift.org/tools/), [Cursor/Xcode integration](https://cursor.com/docs/integrations/xcode)

The official Codex IDE extension supports Cursor, and Codex's ChatGPT login provides subscription access while API-key login uses usage-based billing. CLI and IDE extension share cached authentication. Project config retains the current Codex model and requires ChatGPT login; account allowance and extra-credit settings are separate concerns. [Codex IDE](https://learn.chatgpt.com/docs/codex/ide), [OpenAI authentication](https://learn.chatgpt.com/docs/auth)

Cursor Ultra supplies a separate included allowance; on-demand billing can charge beyond it. The instruction is to use that existing allowance only. Cursor's spending documentation distinguishes included usage from on-demand limits. **Subsequent user confirmation:** Prateek verified that On-demand spending is disabled, resolving that blocker. The configured Playwright connector could not independently inspect the dashboard because Google Chrome was missing. No extra browser was installed, no account billing setting was changed, and no native Cursor inference was started during setup. [Cursor plans](https://cursor.com/docs/models-and-pricing), [Cursor spending controls](https://cursor.com/help/account-and-billing/spend-limits)

## Assessment against the earlier Grok outcome

The new independent assessment strengthens the earlier native-stack conclusion in the [Codex/Grok cross-review](2026-09-22-cross-review.md). It adds code-level evidence for the reason: Snapzy already uses direct macOS capture, OCR, panel, stitching, and SQLite integrations. A web UI would introduce extra language/runtime boundaries without an approved cross-platform requirement.

It also narrows the reuse recommendation. Snapzy persists original image bytes in editable annotation sidecars, and clearing history can leave capture files on disk. Those behaviors differ from the current finalized-only history direction. A suitable stack therefore does not imply that stock Snapzy meets the product requirements. The [source-pinned assessment](2026-09-22-stack-independent-assessment.md) identifies the exact persistence code and proposed verification cases.

## Pocock process: what is complete and what remains

- Complete: primary-source landscape research, original Grok comparison, independent stack analysis, IDE installation, accepted scope/default-on history, initial source and binary checks.
- Subsequently approved: unedited thumbnail dismissal saves to history; editor Done/Copy/Save commits the flattened result; configurable retention of 30 days or 1 GB, whichever limit is reached first, with exported files untouched. See the current product decisions for authoritative scope.
- Awaiting execution: reproducible Intel source build and upstream test results (Snapzy’s current workflow needs full Xcode), hands-on capture/scroll/OCR/permission behavior, and history/redaction lifecycle checks. Released-app evaluation can proceed without a source build.
- Awaiting specification: final shared understanding, accepted testing boundaries, and foundation decision. Then publish the local spec and approved vertical-slice tickets.

No application implementation, upstream fork import, architecture acceptance ADR, commit, or push has been performed as part of this evaluation.
