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

- Azure resource group `CIPP-dev` (separate from production), deployed with upstream's `deployment/cipp-deploy.bicep` (`baseName=cippdev`).
- Runs the image built from `preview/reports`.
- Shares the production **CIPP-SAM** and **CIPP-SSO** app registrations (credentials copied into the dev Key Vault), so it sees every tenant. Because of that it runs with `CIPP_SAM_READONLY=true` (see below).
- Starts with empty CIPP settings: no standards, alerts or scheduled tasks are copied from production, so nothing runs twice against customer tenants.

## Fork-only settings

| App setting | Effect |
|---|---|
| `CIPP_SAM_READONLY=true` | The instance never creates, renews or removes credentials on the CIPP-SAM app registration (weekly Update Tokens timer and `Update-CIPPSAMCertificate`). Use on any instance that borrows another instance's SAM app. Implemented in `Test-CIPPSAMReadOnly`. Candidate for upstream. |

## Copying secrets between vaults

`az keyvault secret show --query value -o tsv` appends a newline; writing that to a file and using `secret set --file` stores the newline as part of the secret. Read with `-o json` and strip trailing CR/LF before writing.

## Keeping in sync with upstream

```
git fetch https://github.com/CyberDrain/CIPP dev
git checkout dev && git merge --ff-only FETCH_HEAD && git push origin dev
git checkout preview/reports && git rebase dev
```
