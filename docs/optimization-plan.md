# Notion2Council Optimization Plan

## Objective

Make Notion2Council installable, release-safe, and easier to validate before publishing.

## Phase 1 — Release and first-run safety

Status: in progress.

- Publish one user-facing Windows package instead of every unpacked Electron runtime file.
- Clean old GitHub Release assets before republishing the same tag.
- Stop automatic release publishing on every push to `master`; use manual workflow dispatch or version tags.
- Use portable repo-local vendor defaults instead of machine-specific `X:\Code\...` paths.
- Add a validation script that checks JSON syntax, PowerShell syntax, Electron entrypoint syntax, release workflow globs, and package-lock version consistency.

## Phase 2 — Build hygiene

Status: planned.

- Replace duplicated version literals with package-version-derived artifact names wherever possible.
- Decide whether the public release should contain one portable EXE, one installer, or one combined archive.
- Add a CI validation workflow that runs on pull requests and pushes without creating releases.
- Make package-lock updates part of the release bump process.

## Phase 3 — Runtime hardening

Status: planned.

- Make vendor mode the default first-run path unless the user explicitly supplies local checkouts.
- Improve user-facing error messages when Python, Git, Node, or upstream checkouts are missing.
- Add service health diagnostics and log summaries after startup failures.
- Validate required upstream files before launching each service.

## Phase 4 — Installer optimization

Status: planned.

- Decide final distribution strategy: portable EXE only, MSI/NSIS installer only, MSIX, or a single ZIP containing selected installers.
- Remove redundant artifacts from release packages.
- Consider code signing and SmartScreen reputation strategy for Windows users.

## Current risk register

| Risk | Impact | Mitigation |
|---|---:|---|
| Stale `package-lock.json` version | Medium | Validation script detects mismatch until lockfile is regenerated. |
| Machine-specific defaults | High | Default config now points to repo-local `vendor/` paths. |
| Release workflow publishing on normal pushes | High | Release workflow should run manually or from tags, not every push. |
| No automated tests | Medium | Add validation script now; add CI workflow next. |
| Combined release ZIP may be redundant | Low/Medium | Decide final artifact strategy in Phase 4. |
