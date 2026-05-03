# Notion2Council Optimization Plan

## Objective

Make Notion2Council installable, release-safe, and easier to validate before publishing.

## Phase 1 — Release and first-run safety

Status: landed.

- Published releases are staged as a single GitHub release ZIP instead of every unpacked Electron runtime file.
- Existing GitHub Release assets are deleted before republishing the same tag.
- Release workflow no longer runs on every push to `master`; releases run from manual workflow dispatch or `v*` tags.
- Normal `master` pushes and pull requests use a separate validation workflow.
- Default config uses portable repo-local `vendor/` paths instead of machine-specific `X:\Code\...` paths.
- Validation checks now cover JSON syntax, PowerShell syntax, Electron syntax, release workflow globs, icon generation, and package-lock/package version consistency.

## Phase 2 — Build hygiene

Status: partially landed.

- `npm run validate:ci` is wired into the Electron build lifecycle.
- The validation workflow installs dependencies, generates icons, runs repository validation, and checks Electron module syntax.
- Remaining: regenerate and commit `package-lock.json` with the current package version if it still differs from `package.json`.
- Remaining: reduce duplicated hardcoded artifact version strings in `package.json` where electron-builder can derive them from `${version}`.

## Phase 3 — Runtime hardening

Status: substantially landed by the runtime refactor.

- Electron runtime has been modularized.
- Main-window sandbox/CSP hardening has been added.
- PowerShell launcher logic has been modularized under `scripts/lib/`.
- Process-tree stop handling, health-check validation, BOM-less UTF-8 state/env writes, and conservative PowerShell syntax formatting have been added.
- Remaining: perform full end-to-end manual smoke test with `npm run electron:dev` and an actual Notion login/session.

## Phase 4 — Installer optimization

Status: planned.

- Decide final distribution strategy: portable EXE only, MSI/NSIS installer only, MSIX, or a single ZIP containing selected installers.
- Remove redundant artifacts from release packages after the preferred distribution type is chosen.
- Consider code signing and SmartScreen reputation strategy for Windows users.

## Current risk register

| Risk | Impact | Mitigation |
|---|---:|---|
| Stale `package-lock.json` version | Medium | Validation detects mismatch unless `-SkipPackageLock` is used; regenerate lockfile before final release. |
| Accidental release on routine push | High | Release workflow is tag/manual only; validation workflow handles normal pushes. |
| Runtime refactor regressions | Medium | Validation workflow checks PowerShell parsing and Electron module syntax; full runtime smoke test still required. |
| Combined release ZIP may be redundant | Low/Medium | Decide final artifact strategy in Phase 4. |
| Unsigned Windows binaries | Medium | Consider signing strategy before public distribution. |
