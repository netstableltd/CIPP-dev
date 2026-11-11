---
description: Set up OpenAI's ChatGPT apps for Microsoft 365 in a tenant, limited to the people you choose and to the access you choose.
---

# ChatGPT for Microsoft 365

OpenAI's ChatGPT apps for Microsoft 365 (Outlook Email, Outlook Calendar, Teams and SharePoint/OneDrive) let people use their mail, calendar, files and Teams from ChatGPT. In the tenant they are one Microsoft Entra app published by OpenAI:

| App | App ID | Publisher |
| --- | --- | --- |
| ChatGPT | `e0476654-c1d5-430b-ab80-70cbd947616a` | OpenAI, L.L.C. (verified) |

Each Microsoft app approved in ChatGPT adds its permissions to this one app's Microsoft Graph grant. OpenAI doesn't publish the app ID; it was confirmed from managed tenants in November 2026. Not covered here: the separate **@ChatGPT** bot in Teams (app `1f5363a7-8b93-4af5-acfa-f7379830d480`, set up from ChatGPT's admin console > Agents) and the ChatGPT iOS app for Intune.

This process adds the app, makes it **assignment-only** so only the people you choose can use ChatGPT with the tenant's data, and gives admin consent for **only the access you choose**. Open it from **Community Additions > ChatGPT for Microsoft 365** with the customer's tenant selected. It is an add-on (`chatgpt-m365`), turned on and off in **Community Additions > Settings > [Add-ons](../../community/settings/addons.md)**. It is modelled on [Claude for Microsoft 365](../claude-m365/README.md).

## How it differs from Claude

* **One app, not two.**
* **No consent page step.** OpenAI starts admin consent from inside ChatGPT (Admin console > Apps > *Review permissions in Microsoft Entra*) and doesn't publish a consent link. That route grants every permission for every action turned on in ChatGPT. Instead, CIPP writes the tenant-wide grant itself with only the chosen read areas and level, so nobody has more access, even for a moment.
* **ChatGPT's own settings must match.** ChatGPT asks Microsoft for the permissions of every action turned on in its admin console. If an action is on but its permission isn't granted, people see *Need admin approval* when they connect. Step 4 shows what to turn off for the chosen level.
* **Higher levels for named people need ChatGPT Enterprise or Edu.** There, a role can have extra actions on. On ChatGPT Business, actions are the same for everyone, so give everyone one level.
* **Shared mailboxes.** ChatGPT can send from and change shared mailboxes and shared calendars (`Mail.Send.Shared`, `Mail.ReadWrite.Shared`, `Calendars.ReadWrite.Shared`). That is only in Level 4.
* **Tasks.** ChatGPT's Teams app reads and manages Planner and To Do tasks, so tasks are a read area of their own.

## Information for the customer

As for Claude: the box at the top shows what the tenant already has of what we recommend first (third-party backup, Entra ID P1, Microsoft Defender, Business Premium) and makes a branded PDF to send them. The PDF also asks which ChatGPT plan they have.

## Access levels

| Level | ChatGPT can | Graph permissions added | Turn off in ChatGPT |
| --- | --- | --- | --- |
| 1. Read only | Search and read email, contacts, calendar, files, Teams, meetings and tasks | none | Every write action of the Microsoft apps |
| 2. Drafts and tidy-up | Also write drafts; move, label and delete email in the person's own mailbox | `Mail.ReadWrite` | Sending, contacts, and every Calendar, Teams and SharePoint write action |
| 3. Personal assistant | Also send and forward email, manage meetings, contacts, tasks, out-of-office and mail rules | `Mail.Send`, `MailboxSettings.ReadWrite`, `Contacts.ReadWrite`, `Calendars.ReadWrite`, `OnlineMeetings.ReadWrite`, `Tasks.ReadWrite` | Shared mailbox and shared calendar actions, Teams messages and channels, every SharePoint write action |
| 4. Full access | Also send from shared mailboxes, change OneDrive and SharePoint files, post in Teams | `Mail.ReadWrite.Shared`, `Mail.Send.Shared`, `Calendars.ReadWrite.Shared`, `Tasks.ReadWrite.Shared`, `Files.ReadWrite.All`, `Sites.ReadWrite.All`, `ChatMessage.Send`, `ChannelMessage.Send`, `Chat.Create`, `Channel.Create` | Nothing |

Read areas: email and contacts, calendar, OneDrive and SharePoint files, Teams chats and channels (including `Group.Read.All` and `User.Read.All`, which ChatGPT's Teams app asks for), Teams meetings, Planner and To Do tasks. Always kept: `openid`, `profile`, `email`, `offline_access`, `User.Read`, `User.ReadBasic.All`, `People.Read`, `MailboxSettings.Read` (time zone).

The levels, the read areas, their wording in the PDF, their permissions and what to turn off in ChatGPT are in `backend/Config/Addons/chatgpt-m365/ChatGPTConnectorAccess.json`. ChatGPT can only ever do what the person using it could do themselves.

## Current setup

The top of the page shows:

* whether the app is in the tenant, has admin consent, requires assignment, and who is assigned;
* the access group and its members;
* whether users can approve apps themselves, and whether admin consent requests are on;
* everyone's level and what ChatGPT can read, and anyone with their own level;
* **people who approved ChatGPT for themselves**, for example from before user consent was turned off;
* **other permissions ChatGPT holds**, outside Microsoft Graph. For example SharePoint Online's `MyFiles.Read` and `AllSites.Read` from a person approving the SharePoint app. The levels don't manage these, so they are listed to be checked;
* whether the tenant has Entra ID P1.

## Steps

1. **Add the ChatGPT app.** Adds the app to the tenant if it isn't there. This gives it no access.
2. **Choose who can use ChatGPT.** As for Claude: an access group (default `SG-ChatGPT-Users`), or people assigned directly for tenants without Entra ID P1. Then **Assignment required**, and optionally stopping users from approving apps themselves (with admin consent requests reviewed by Global Administrators). This step doesn't need consent first.
3. **Choose what ChatGPT can read and change.**
   * **No consent yet:** **Give consent for this access** creates the tenant-wide grant with the permissions that are always kept, the chosen read areas and the level for everyone.
   * **Consent already there** (for example someone approved it in ChatGPT, which usually gives everything): **Save access** sets it to exactly the chosen level.
   * Higher levels for named people work as for Claude: a per-person grant with only what their level adds.
   * Saving also removes any approvals people gave themselves.
4. **Match it in ChatGPT** (by hand, as a workspace owner or admin):
   * Admin console > Apps: turn on the Microsoft apps you want.
   * Turn off the actions above the chosen level. The page shows which, for the level chosen.
   * Set the apps' action permission to *Allow read actions* or *Always ask*, so ChatGPT asks before it sends or changes anything.
   * On Enterprise/Edu, give people with a higher level a role with those actions on.
   * Don't run *Review permissions in Microsoft Entra* with more actions on than the level allows. If someone does, save step 3 again.
   * If the tenant uses Conditional Access, include the ChatGPT app in its MFA policy.

## Summary for the customer

As for Claude: a branded PDF of what was set up, read from the tenant at that moment, with an optional connection guide (a Word document uploaded once per CIPP instance) at the end.

## To test before using with customers

* Connect a test user at Level 1 with the write actions off in ChatGPT, and check there's no *Need admin approval* prompt.
* Then turn one write action on in ChatGPT without raising the level, and check that people get the prompt and an admin consent request. That shows the levels hold.
* Check whether ChatGPT's SharePoint search also needs SharePoint Online's `MyFiles.Read`/`AllSites.Read` tenant-wide. If it does, add them to the files area.

## Permissions

Viewing the setup and making the customer PDFs need `Tenant.Application` Read. Making changes needs `Tenant.Application` Read/Write. CIPP uses its own access to the tenant (GDAP) for everything, including giving admin consent.

Sources: OpenAI's help articles on [admin permissions for apps](https://help.openai.com/en/articles/11509118), [Outlook](https://help.openai.com/en/articles/12512241), [Teams](https://help.openai.com/en/articles/12552368) and [SharePoint](https://help.openai.com/en/articles/12143177).

## API

| Endpoint | Method | Parameters |
| --- | --- | --- |
| `ListChatGPTConnector` | GET | `tenantFilter`, `GroupName` (optional) |
| `ExecChatGPTConnector` | POST | `tenantFilter`, `Action` (`AddApps`, `Apply` or `Access`), `Users` (user ids or sign-in names), `GroupName`, `AssignUsersDirectly`, `LockUserConsent`, `RemoveOtherDirect`; for `Apply` and `Access`: `ReadAreas` (`mail`, `calendar`, `files`, `teams`, `meetings`, `tasks`), `TenantLevel` (`read`, `drafts`, `assistant`, `full`), `PeopleLevels` (`[{ User, Level }]`). With no consent yet, `Access` needs both `ReadAreas` and `TenantLevel`. |
| `ExecChatGPTConnectorCustomerPdf` | POST | `tenantFilter`, `ContactName`, `PreparedBy` (both optional). Returns `application/pdf`. |
| `ExecChatGPTConnectorSummaryPdf` | POST | `tenantFilter`, `GroupName`, `ContactName`, `PreparedBy`, `IncludeGuide` (all but `tenantFilter` optional). Returns `application/pdf`. |
| `ExecAddonGuide` (shared) | POST | `AddonId` `chatgpt-m365`, `Key` `connection`, `Action` (`Upload` or `Remove`); for `Upload`: `FileName` (.docx) and `Data` (base64 or a data URL, up to 10 MB). |

`ExecChatGPTConnector` returns `Results`, a list of steps with `Step`, `Status` (`Success`, `Info`, `Warning` or `Error`) and `Message`, and `Success` (no step failed).
