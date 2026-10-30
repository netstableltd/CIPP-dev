---
description: Set up Anthropic's Claude connector for Microsoft 365 in a tenant, limited to the people you choose.
---

# Claude for Microsoft 365

Anthropic's Claude connector for Microsoft 365 lets people use their mail, calendar, files and Teams from Claude. In the tenant it is two Microsoft Entra apps published by Anthropic:

| App | App ID |
| --- | --- |
| M365 MCP Client for Claude | `08ad6f98-a4f8-4635-bb8d-f1a3044760f0` |
| M365 MCP Server for Claude | `07c030f6-5743-41b7-ba00-0a6e85f37c17` |

This process adds both apps and makes them **assignment-only**, so only the people you choose can use Claude with the tenant's data. Open it from **Community Additions > Claude for Microsoft 365** with the customer's tenant selected. It is an add-on (`claude-m365`), turned on and off in **Community Additions > Settings > [Add-ons](../../community/settings/addons.md)**.

## Information for the customer

The box at the top of the page is for when a customer asks for Claude. It shows what the tenant already has of what we recommend first, and makes a branded PDF to send them:

| Check | How CIPP finds it |
| --- | --- |
| Third-party backup | An enterprise app from a Microsoft 365 backup product. Barracuda Cloud-to-Cloud Backup is recognised by its app ID (`09e6e8ef-2c94-4106-89dd-d0a7e500a886`; in Entra it is called just *Cloud-to-Cloud-Backup*). Barracuda's other apps (*Barracuda M365 Link*, *BarracudaONE*) are not backup and don't count; other products (Datto, Veeam, AvePoint, Acronis, Dropsuite, SkyKick and others) are listed. A backup that doesn't use an enterprise app isn't found. |
| Entra ID P1 | An active licence with the `AAD_PREMIUM` or `AAD_PREMIUM_P2` service plan. |
| Microsoft Defender | An active licence with Defender for Business, Defender for Endpoint, or Defender for Office 365. |
| Business Premium | A Microsoft 365 Business Premium licence (E3 and E5 are named too). |

The PDF (**Preview PDF** or **Download PDF**) uses the CIPP branding and has:

* the request: there are various ways to give Claude access, and we recommend starting with limited access;
* **Before you start**: a third-party backup, Entra ID P1 and Microsoft Defender, each with whether the customer has it, and a note on Microsoft 365 Business Premium as our default;
* **Access levels**: a comparison table, then each level with what Claude can and can't do and its pros and cons (two levels to a page);
* **Next steps**: how we keep it safe, and a list to copy into their reply: who, a level for everyone, higher levels for named people, anything Claude shouldn't read, and quotes for anything missing.

**Addressed to** and **From** are optional names for the letter.

## Access levels

| Level | Claude can | Graph permissions added |
| --- | --- | --- |
| 1. Read only | Search and read email, calendar, files and Teams | none |
| 2. Drafts and tidy-up | Also write drafts; move, label and delete email in the person's own mailbox | `Mail.ReadWrite` |
| 3. Personal assistant | Also send and forward email, manage meetings, out-of-office and mail rules | `Mail.Send`, `Calendars.ReadWrite`, `MailboxSettings.ReadWrite` |
| 4. Full access | Also change OneDrive and SharePoint files, and post in Teams | `Files.ReadWrite.All`, `ChatMessage.Send`, `ChannelMessage.Send`, `Chat.Create` |

The levels, their wording in the PDF and their permissions are in `backend/Config/Addons/claude-m365/ClaudeConnectorAccess.json`. Claude can only ever do what the person using it could do themselves; Claude can read shared mailboxes but can't change them at any level.

## Current setup

The top of the page shows where the tenant is: whether each app is there, has admin consent, requires assignment and who is assigned; the access group and its members; whether users can approve apps themselves; whether admin consent requests are on; everyone's access level and what Claude can read, and anyone with their own level; and whether the tenant has Entra ID P1. **Check again** re-reads it.

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
   The people list starts with whoever can use Claude now (the group's members, or the people assigned directly).
4. **Choose what Claude can read and change.** **Save access** sets, on the *M365 MCP Server for Claude* app's Microsoft Graph permissions:
   * **What Claude can read, for everyone**: email, calendar, OneDrive and SharePoint files, Teams chats and channels, Teams meetings. Switching one off removes its read permissions for everyone.
   * **Access level for everyone**: the write permissions of everyone are set to exactly the chosen level's.
   * **Higher levels for named people**: each person gets their own grant with only the permissions their level adds on top of everyone's. Removing a person from the list, or choosing a level no higher than everyone's, removes their grant. A person also needs to be one of the people who can use Claude (step 3).

   Microsoft's consent page approves every permission Anthropic's app asks for, including the write ones, so straight after step 2 everyone has Level 4. The page warns about this and starts the choice at Level 1. **If anyone approves the consent page again, save this step again.** A write permission that also reads (for example `Mail.ReadWrite`) lets Claude read that area for the person even if the area is switched off; the results say so.
5. **Finish in Claude** (by hand):
   * in Claude, as an owner of the customer's Team or Enterprise organisation: Organisation settings > Connectors > add Microsoft 365;
   * if the tenant uses Conditional Access, include the two Claude apps in its MFA policy;
   * optionally, for the Claude desktop app, hide write tools on some devices with the managed configuration's `toolPolicy`.

## Summary for the customer

When setup is done, **Summary for the customer** at the bottom of the page makes a branded PDF to send them, read from the tenant as it is at that moment:

* **What we've set up**: how many people can use Claude, everyone's level and how many have a higher one; a table of each person with their level and what Claude can do for them; what Claude can read; and a **Still to finish** box if consent hasn't been given, Claude isn't limited to named people yet, or everyone still has full access from the consent page.
* **Keeping it safe**: named people only, no unapproved apps, app requests reviewed, third-party backup and Microsoft Defender, each *In place* or *Not in place*, with a recommendation for anything missing; and what happens next (connecting Microsoft 365 in Claude, approving before it sends, asking us for changes, reporting anything odd).

**Addressed to** and **From** are optional, as for the information PDF.

### Connection guide

Your own step-by-step guide for users, as a Word document, can go at the end of the summary. Upload it with **Upload guide (.docx)** on the summary card; it is kept in this CIPP instance (not in the code) and used for every customer. **Replace guide** swaps it, **Remove** deletes it, and **Add the connection guide to the end of the summary** leaves it out of one PDF.

The document is redrawn in the PDF's own style rather than attached as it is:

* the opening lines: a short all-capitals label is dropped, the next line becomes the page title and the one after it the subtitle;
* headings (Word heading styles, or a short all-bold line) and numbered steps such as "1  Open Settings" become section headings;
* paragraphs keep bold and italic; bulleted and numbered lists become bullet lists;
* pictures appear at their size in the document; pictures side by side in a table appear side by side;
* a one-cell table (a boxed note) becomes a callout, shown as a warning when its first line contains "important", "warning", "caution" or "note";
* other tables become tables; headers, footers and comments are left out.

Uploading checks that the document can be read first. Changing the guide needs `CIPP.AppSettings` Read/Write.

Every step checks what is already there, so running the process again only changes what is missing. Each change is written to the CIPP log under `ExecClaudeConnector`.

## Permissions

Viewing the setup and making the customer PDFs need `Tenant.Application` Read; making changes needs `Tenant.Application` Read/Write. CIPP uses its own access to the tenant (GDAP) for everything except the consent page.

Sources: Anthropic's [Connect to Microsoft 365](https://claude.com/docs/third-party/claude-desktop/connectors-m365) and [Microsoft 365 connector security guide](https://support.claude.com/en/articles/12684923).

## API

| Endpoint | Method | Parameters |
| --- | --- | --- |
| `ListClaudeConnector` | GET | `tenantFilter`, `GroupName` (optional) |
| `ExecClaudeConnector` | POST | `tenantFilter`, `Action` (`AddApps`, `Apply` or `Access`), `Users` (user ids or sign-in names), `GroupName`, `AssignUsersDirectly`, `LockUserConsent`, `RemoveOtherDirect`; for `Apply` and `Access`: `ReadAreas` (`mail`, `calendar`, `files`, `teams`, `meetings`), `TenantLevel` (`read`, `drafts`, `assistant`, `full`), `PeopleLevels` (`[{ User, Level }]`) |
| `ExecClaudeConnectorCustomerPdf` | POST | `tenantFilter`, `ContactName`, `PreparedBy` (both optional). Returns `application/pdf`. |
| `ExecClaudeConnectorSummaryPdf` | POST | `tenantFilter`, `GroupName`, `ContactName`, `PreparedBy`, `IncludeGuide` (all but `tenantFilter` optional). Returns `application/pdf`. |
| `ExecClaudeConnectorGuide` | POST | `Action` (`Upload` or `Remove`); for `Upload`: `FileName` (.docx) and `Data` (base64 or a data URL, up to 10 MB). |

`ExecClaudeConnector` returns `Results`, a list of steps with `Step`, `Status` (`Success`, `Info`, `Warning` or `Error`) and `Message`, and `Success` (no step failed).
