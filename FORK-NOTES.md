# netstableltd/CIPP-dev – fork notes

This fork of [CyberDrain/CIPP](https://github.com/CyberDrain/CIPP) is where Netstable develops a **Reports** area for CIPP (a consolidated Reports menu, scheduled internal pre-check and customer reports, and third-party report integrations starting with Atera). The intent is to offer the work back upstream as pull requests to `CyberDrain/CIPP:dev`.

Design notes live with the project docs (see `docs/06-reports-module-design.md` in the project folder; they will be moved into this repo once stable).

## Branches

| Branch | Purpose |
|---|---|
| `dev` | Mirror of upstream `dev`. Do not commit here; sync from upstream. |
| `main` | Mirror of upstream `main`. |
| `preview/reports` | Working branch for the Reports feature. Every push builds `ghcr.io/netstableltd/cipp-dev:preview-reports` via upstream's `preview-container.yml`. |

Feature work for upstream PRs is split out from `preview/reports` into `feat/*` branches based on upstream `dev`, using conventional commits.

## Dev instance

- A separate Azure deployment from production, deployed with upstream's `deployment/cipp-deploy.bicep`, running the image built from `preview/reports`. (Environment details are kept in private notes, not in this public repo.)
- When a dev instance borrows production's SAM app registration it runs with `CIPP_SAM_READONLY=true` (see below).
- Starts with empty CIPP settings: no standards, alerts or scheduled tasks are copied from production, so nothing runs twice against customer tenants.

## Fork-only settings

| App setting | Effect |
|---|---|
| `CIPP_SAM_READONLY=true` | The instance never creates, renews or removes credentials on the CIPP-SAM app registration (weekly Update Tokens timer and `Update-CIPPSAMCertificate`). Use on any instance that borrows another instance's SAM app. Checked inline (`$env:CIPP_SAM_READONLY -eq 'true'`) in `Start-UpdateTokensTimer` and `Update-CIPPSAMCertificate`, so upstream's tests run unchanged. Candidate for upstream. |

## Community Additions add-ons

Community Additions are packaged as **add-ons** (user docs: `docs/user-documentation/community/settings/addons.md`). Each has a manifest at `backend/Config/Addons/<id>/addon.json` and its parts in `Addons/<id>` folders (`backend/Config/AddonLayout.json`); pages are at `/addons/<id>`. Add-on #1 is `claude-m365`.

What the add-on system touches outside its own folders (check these when merging upstream):

| File | Change |
|---|---|
| `Get-CIPPFeatureFlag.ps1`, `Set-CIPPFeatureFlag.ps1` | Add one flag per add-on (`Addon.<id>`, from `Get-CIPPAddonFeatureFlags`), so turning an add-on off hides its pages and refuses its endpoints through the normal flag checks. |
| `frontend/src/layouts/config.jsx` | `nativeMenuItems` is wrapped in `withAddonMenuItems` (`utils/addon-menu.js`), which adds the add-ons' menu entries at build time; Community Additions header with Settings > Add-ons. |
| `frontend/tests/mocks/require-context.js` | Maps the add-on manifest and extension-file globs for vitest. |
| `frontend/src/pages/identity/administration/users/patch-wizard.jsx` | Extension point `userBulkEdit` (with `src/utils/addon-extensions.js`): add-on properties in Edit Properties, sent to the add-on's endpoint and never to PatchUser. Kept to small, marked (`Fork:`) additions; the file is not reformatted, so upstream merges stay clean. Covered by `frontend/tests/pages/UsersPatchWizard.addonExtension.test.jsx`. |
| `build/Dockerfile` | `build-addonpackages` stage (packages each add-on into `Config/AddonPackages/<id>.zip` for the manager's downloads; fails the build if an add-on doesn't pass the package checks) and copies `backend/Config/Addons` beside the frontend build for the menu. `Dockerfile.release` is not changed. |

The manager (Community Additions > Settings > Add-ons) is `ListAddons`, `ExecAddon` and `ExecAddonDownload` (`HTTP Functions/CommunityAdditions`), on functions in `CIPPCore/Public/AddonManager`. Uploads are only checked and stored (table `AddonPackages`), never run: installing is `build/tools/addons/Install-CippAddon.ps1`, then commit and push.

Shared pieces add-ons can use (core, not inside any add-on): `CIPPCore/Public/AddonKit` (`ConvertFrom-CIPPDocxGuide`, `Get-CIPPAddonGuide`), the `ExecAddonGuide` endpoint (Word guides listed under `guides` in a manifest, stored in table `AddonGuides`), and `frontend/src/components/CippAddons` (`CippAddonPdfCard`, `CippAddonStepResults`, `CippAddonGuideUpload`). Add-on #2 is `shared-mailbox`; #3, `bulk-email-domain`, is the first to add to a CIPP page (Users > Edit Properties) and is a candidate for an upstream PR (follows CyberDrain/CIPP#6013). The Claude add-on still has its own copies of the PDF card, step results and guide upload (guide in table `CommunityProcesses`); moving it onto the kit is a later tidy-up.

Old URLs `/community/standard-processes(/claude-m365)` redirect to the new ones; remove those two pages once nobody uses them.

## Copying secrets between vaults

`az keyvault secret show --query value -o tsv` appends a newline; writing that to a file and using `secret set --file` stores the newline as part of the secret. Read with `-o json` and strip trailing CR/LF before writing.

## Keeping in sync with upstream

```
git fetch https://github.com/CyberDrain/CIPP dev
git checkout dev && git merge --ff-only FETCH_HEAD && git push origin dev
git checkout preview/reports && git rebase dev
```

Before merging a new upstream version, check the add-ons against it, and after testing add the version to each add-on's `cipp.testedWith` (the add-on tests fail until you do):

```
pwsh build/tools/addons/Test-CippAddonUpstream.ps1 -Ref dev
```
