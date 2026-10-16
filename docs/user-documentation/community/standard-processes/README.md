---
description: Repeatable jobs in a customer tenant, each as a guided page.
---

# Standard Processes

**Community Additions > Standard Processes** lists jobs that are done the same way in every tenant. Each one is a guided page: pick a tenant with the tenant selector, open the process and follow its steps. Every process reads what is already in place first, so running it again is safe.

| Process | What it does | Permission |
| --- | --- | --- |
| [Claude for Microsoft 365](claude-m365.md) | Adds Anthropic's Claude connector for Microsoft 365 and limits it to chosen people. | `Tenant.Application` |

A card is only shown to people with the permission it needs.

## Adding a process

1. Add an entry to `frontend/src/data/standardProcesses.js` (title, summary, steps, permissions, page path).
2. Add the page under `frontend/src/pages/community/standard-processes/`. Keep the page a thin wrapper around a component in `src/components/CippCommunity/`.
3. Put the backend work in a `CIPPCore` function under `Public/CommunityAdditions/`, exposed by `List…` (read-only status) and `Exec…` (changes) endpoints under `HTTP Functions/CommunityAdditions/`. Make every step check before it changes anything, and return a list of steps (`Step`, `Status`, `Message`) for the page to show.
4. Add Pester tests (`backend/Tests/CommunityAdditions/`) and a vitest test, and a docs page here.
