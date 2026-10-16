---
description: Set up Anthropic's Claude connector for Microsoft 365 in a tenant, limited to the people you choose.
---

# Claude for Microsoft 365

Anthropic's Claude connector for Microsoft 365 lets people use their mail, calendar, files and Teams from Claude. In the tenant it is two Microsoft Entra apps published by Anthropic:

| App | App ID |
| --- | --- |
| M365 MCP Client for Claude | `08ad6f98-a4f8-4635-bb8d-f1a3044760f0` |
| M365 MCP Server for Claude | `07c030f6-5743-41b7-ba00-0a6e85f37c17` |

This process adds both apps and makes them **assignment-only**, so only the people you choose can use Claude with the tenant's data. Open it from **Community Additions > Standard Processes > Claude for Microsoft 365** with the customer's tenant selected.

## Current setup

The top of the page shows where the tenant is: whether each app is there, has admin consent, requires assignment and who is assigned; the access group and its members; whether users can approve apps themselves; whether admin consent requests are on; and whether the tenant has Entra ID P1. **Check again** re-reads it.

## Steps

1. **Add the Claude apps.** Adds the two apps to the tenant if they aren't there. Both must exist before Microsoft's consent page will work for the client app.
2. **Approve Microsoft's consent page.** Each button opens Microsoft's admin consent page in a pop-up. Sign in as a **Global Administrator of the customer's tenant** and accept, for the client and then the server. CIPP can't do this step for you: the permissions are Anthropic's, and the consent page grants exactly what the app asks for. The page checks every few seconds and ticks each app off once Microsoft has recorded the consent.
3. **Choose who can use Claude.** Pick the people, then **Apply**. CIPP:
   * creates the access group (default `SG-Claude-Users`, a security group) or reuses it, and adds the people;
   * assigns the group to both apps, then turns on **Assignment required** on both. If an assignment fails, Assignment required is left as it was so nobody is locked out;
   * removes direct assignments for people who are now in the group. Anyone else assigned directly is reported and left in place, unless **Remove anyone assigned directly who isn't in the group** is on.

   Assigning a group to an app needs **Entra ID P1** (Business Premium includes it). For a tenant without it, the page switches on **Assign people directly**, which assigns each person to both apps instead of using a group.

   With **Also stop users approving apps themselves** on (the default), CIPP also:
   * removes users' permission to consent to apps themselves. If CIPP's *Require admin consent for applications* standard already manages this, it is left alone. Apps people approved before are not removed (Entra > Enterprise apps > Permissions);
   * turns on **admin consent requests** with Global Administrators as reviewers. Existing reviewers are kept.
4. **Finish in Claude** (by hand):
   * in Claude, as an owner of the customer's Team or Enterprise organisation: Organisation settings > Connectors > add Microsoft 365;
   * if the tenant uses Conditional Access, include the two Claude apps in its MFA policy;
   * to stop Claude sending email or changing files, remove those Graph permissions from the apps in Entra.

Every step checks what is already there, so running the process again only changes what is missing. Each change is written to the CIPP log under `ExecClaudeConnector`.

## Permissions

Viewing the setup needs `Tenant.Application` Read; making changes needs `Tenant.Application` Read/Write. CIPP uses its own access to the tenant (GDAP) for everything except the consent page.

## API

| Endpoint | Method | Parameters |
| --- | --- | --- |
| `ListClaudeConnector` | GET | `tenantFilter`, `GroupName` (optional) |
| `ExecClaudeConnector` | POST | `tenantFilter`, `Action` (`AddApps` or `Apply`), `Users` (user ids or sign-in names), `GroupName`, `AssignUsersDirectly`, `LockUserConsent`, `RemoveOtherDirect` |

`ExecClaudeConnector` returns `Results`, a list of steps with `Step`, `Status` (`Success`, `Info`, `Warning` or `Error`) and `Message`, and `Success` (no step failed).
