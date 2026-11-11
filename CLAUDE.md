# CLAUDE.md – netstableltd/CIPP-dev

Instructions for Claude Code working in this repository. This file is public: no customer names, tenant
details, secrets or instance URLs here. Those live in Dave's private notes (`HANDOFF-PRIVATE.md` /
`LOCAL-NOTES.md` in his local project folder), which Claude should read if they are available.

## What this repo is

A fork of [CyberDrain/CIPP](https://github.com/CyberDrain/CIPP) (CIPP-NG: PowerShell backend in
`backend/`, Next.js frontend in `frontend/`, built into one container by `build/Dockerfile`). Netstable
(Dave Webster, an MSP) uses it to build features that may later go upstream as PRs.

- **Working branch:** `preview/reports`. Every push builds `ghcr.io/netstableltd/cipp-dev:preview-reports`
  via `.github/workflows/preview-container.yml`; the dev instance runs that image.
- `dev` and `main` mirror upstream `dev` and `main` (never commit to them).
- Currently based on **CIPP 11.3.0** (merged 4 Nov 2026). Upstream `dev` was ~30 commits ahead then.
- Read `FORK-NOTES.md` first: it lists every change the fork makes to upstream files and why.

## Work in this fork

- **Reports** (Reports menu, report PDFs via the CIPPSharp renderer, Atera integration): parked.
- **Community Additions add-ons** (active). Each add-on is a manifest `backend/Config/Addons/<id>/addon.json`
  plus files in `Addons/<id>` folders (layout in `backend/Config/AddonLayout.json`); pages at `/addons/<id>`.
  User docs: `docs/user-documentation/community/settings/addons.md`.
  - `claude-m365`: Claude for Microsoft 365 connector setup, access levels, customer PDFs.
  - `shared-mailbox`: customer questions PDF, create/configure a shared mailbox, "ready" PDF.
  - `bulk-email-domain`: "Email Domain" in Users > Edit Properties (alias or primary address in bulk).
    First add-on that extends a CIPP page; candidate for an upstream PR (follows CyberDrain/CIPP#6013).
  - Manager: Community Additions > Settings > Add-ons (`ListAddons`, `ExecAddon`, `ExecAddonDownload`).
  - Shared kit: `backend/Modules/CIPPCore/Public/AddonKit`, `AddonManager`, `frontend/src/components/CippAddons`,
    extension points in `frontend/src/utils/addon-extensions.js`.
  - Tools in `build/tools/addons`: Export / Install / Uninstall, `Update-CippAddonDependencies.ps1`
    (run after changing an add-on's code; tests fail if `dependsOn` is stale) and
    `Test-CippAddonUpstream.ps1` (run before merging a new upstream version).

## Rules

- **Security and data:** never commit customer data, tenant names or secrets. Tests use synthetic data
  only. Uploaded customer/MSP documents (for example Word guides with screenshots) are stored in the
  instance, never in the repo. Never print API keys or storage keys; treat any key Dave gives as
  per-session.
- **Dev must never rotate the shared SAM app's credentials:** keep the inline
  `$env:CIPP_SAM_READONLY -eq 'true'` checks in `Start-UpdateTokensTimer` and `Update-CIPPSAMCertificate`
  through every upstream merge.
- **Don't change live CIPP**, and don't run changes against customer tenants unless Dave asks for that
  specific change. The dev instance is connected to real customer tenants.
- **Touching upstream files:** keep changes small and marked `// Fork:` / `# Fork:`, list them in
  `FORK-NOTES.md`, and don't reformat upstream files (no prettier on them) so merges stay clean.
- **Writing style:** plain UK English, short and direct, user-facing text says what happens, not how
  it's built.
- **Commits:** conventional commits (`feat(community): …`, `fix(addons): …`). Commit or push only when
  Dave asks or when finishing a task he asked for that ends in a deploy.

## Build, test, deploy

PowerShell isn't installed natively in the cloud container; run it in Docker (`mcr.microsoft.com/powershell`
with git and Pester 5.7.1 added). Locally, PowerShell 7 + Pester 5 works directly.

```bash
# Backend tests (all, or a folder)
pwsh -c "Invoke-Pester -Path backend/Tests -Output Normal"
pwsh -c "Invoke-Pester -Path backend/Tests/Addons -Output Detailed"

# Regenerate the API spec after adding or changing an endpoint (committed: backend/Config/openapi.json)
pwsh -File build/tools/build-openapi.ps1

# Frontend (from frontend/): install, lint, tests, production build
yarn install --frozen-lockfile --ignore-engines
npx eslint <changed files>
npx vitest run --shard=1/3 --maxWorkers=2   # the full suite in one go can run out of memory; shard it
npx next build --webpack                    # never `yarn build`: it deletes package.json and yarn.lock
```

Known failures that are not ours: 9 backend time-zone tests fail in a container without time-zone data.
Upstream 11.3.0 itself has 50 eslint errors / 289 warnings; compare against upstream before blaming the fork.

**Deploy to dev:** push `preview/reports` → wait for the "Build: Preview Container" run
(`gh run list -R netstableltd/CIPP-dev -b preview/reports`) → restart the dev web app (often needs a second
restart, as the first can pick up the old image) → check `/version.json` shows the new commit.

## Upstream merges

```bash
git fetch https://github.com/CyberDrain/CIPP 'refs/tags/*:refs/tags/upstream/*'
pwsh build/tools/addons/Test-CippAddonUpstream.ps1 -Ref upstream/vX.Y.Z   # BREAK / REVIEW / FORK report
git tag pre-X.Y.Z-merge && git merge --no-ff upstream/vX.Y.Z
```

Then check the fork changes in `FORK-NOTES.md` survived (SAM read-only checks, feature-flag merge,
Dockerfile add-on stages, `config.jsx` menu wrapper, `patch-wizard.jsx` hooks), check any new code that
writes app credentials, regenerate the API spec, run all tests, and add the new version to
`cipp.testedWith` in each add-on's `addon.json` (the add-on guard tests fail until you do).

## Gotchas learned the hard way

- **Frontend extension files must stay light.** Files found by `require.context` (add-on manifests,
  `userBulkEdit.js`) load with CIPP and during vitest setup. Importing a component at their top level pulled
  the real `ApiCall` module in before test mocks and broke 116 unrelated tests. Use `React.lazy` for components.
- New `require.context` globs need a matching entry in `frontend/tests/mocks/require-context.js`.
- **PowerShell `@($x.Missing)` is `@($null)`, a one-item list.** Filter with `Where-Object { $_ }` when
  a manifest field may be absent (this broke the add-on manager page once).
- Pester 5 doesn't allow `BeforeEach` at the file root: wrap tests in a top-level `Describe`.
- Method-call arguments: `$list.Add(($a -replace 'x', 'y'))` needs the extra parentheses, or the comma
  splits arguments.
- `ApiPostCall`/`ApiGetCall` come from `src/api/ApiCall`; tests mock it with `tests/mocks/api-call.js`.
- MUI Switch has role `switch`; `@mui/icons-material` 9 has `HelpOutlined`, not `HelpOutline`.
- Exchange from CIPP: `New-ExoRequest` (one cmdlet) and `New-ExoBulkRequest` (batched; pass `OperationGuid`
  per request to match results). Proxy addresses are changed the way `Invoke-EditUserAliases` does it.
