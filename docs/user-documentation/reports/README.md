---
description: Monthly customer reports and an internal pre-check, built from Microsoft 365 and RMM/PSA data.
---

# Reports

The **Reports** area produces a branded monthly report for each customer, and an internal **pre-check** a few days before it so problems can be fixed before the customer sees them. It collates what CIPP already knows about each tenant (from the nightly Reporting DB cache) with data from integrations such as [Atera](../cipp/integrations/atera.md).

{% content-ref url="companies.md" %}
[companies.md](companies.md)
{% endcontent-ref %}

{% content-ref url="review.md" %}
[review.md](review.md)
{% endcontent-ref %}

{% content-ref url="device-rules.md" %}
[device-rules.md](device-rules.md)
{% endcontent-ref %}

{% content-ref url="settings.md" %}
[settings.md](settings.md)
{% endcontent-ref %}

The Reports area needs the `CIPP.Reports` permission. Read lets a role see companies and settings; Read/Write lets it change them and run test reports.

## The customer report

Each company's report is one PDF assembled from an ordered list of **sections**. Choose the sections per company (Reports > Companies > Edit report settings > Report sections, drag to reorder) or set a default list in [Settings](settings.md). Sections without data for a company are left out.

| Section | What it shows | Data |
| --- | --- | --- |
| Summary | Headline figures, overall status and an optional note from your team | All |
| Your computers | Every computer with its user, Windows version, hardware, last seen and a status (Good / Check / Needs attention, from the [Device Rules](device-rules.md)), and why | RMM |
| Updates | Security and other Microsoft updates waiting or failing on each computer (from the RMM's patch scan), last security update, and the date each Windows version stops receiving security fixes | RMM |
| Computer health | High memory use during working hours (add RAM), drives filling up (clear space or a bigger drive), hardware below or close to the minimum in the [Device Rules](device-rules.md), Windows Home | RMM |
| Monitoring alerts | Alerts in the month by severity and the most common | RMM |
| Support requests | Tickets opened and resolved, who raised them, time spent | PSA |
| Purchases | Items bought this month and over the last 12 months, from invoices | PSA |
| Microsoft 365 security | Secure Score with trend, MFA coverage | CIPP cache |
| Users & licences | Users, guests and licences with spare seats | CIPP cache |
| Email & domains | Fullest mailboxes; SPF, DKIM and DMARC per domain | CIPP cache |
| Data breaches | Email addresses on the tenant's domains found in known breaches (CIPP's breach lookup, run when the report is generated), with breach dates and what was exposed from Have I Been Pwned's public catalogue. Passwords are never shown | Breach lookup |
| Microsoft 365 baseline | CIPP's full Executive Summary (standards, Secure Score, licences, devices, Conditional Access). Opt-in: useful for a first report or quarterly | CIPP cache |
| Recommendations | What to do now and what to plan for, from the pre-check | All |

Any template designed in the [Report Builder](../tools/report-builder/README.md) can also be added as a section. It is filled with the company's data when the report is generated; a source filtered on **"is a date in" > The report period** covers the month being reported on.

## The pre-check

The pre-check runs the same data through a set of rules and sorts findings into:

* **Block** - the report would be wrong or empty (no Microsoft 365 data, a connection error, no RMM mapping).
* **Fix** - should be sorted before the report goes out; if still open, it appears in the customer's Recommendations.
* **Info** - worth knowing; items with customer wording appear under "To plan for".

Rules include admins or users without enforced MFA, a Secure Score drop, unassigned licences, addresses in data breaches, devices not seen for 30 days, unsupported or soon-unsupported Windows, security updates waiting or failing, high memory use in working hours, drives filling up, hardware below or close to the minimum, Windows Home, devices not restarted for 30 days, mailboxes 80% full, domains missing SPF/DKIM/DMARC, old urgent tickets, closed tickets with no time, and contracts ending.

## Review before sending

Create a draft of a company's report, change the note, sections and recommendations, approve it and send it from [Review](review.md).

## Test runs

Every company has **Test customer report** and **Test pre-check** actions. They generate the report now and email it only to the addresses you type - never to the company's recipients. Test reports are marked TEST and appear under Report Builder > Generated Reports.

## Menu

The Reports menu holds Companies, Review, the Report Builder, Device Rules and Settings. Turn on **Reports Menu** under CIPP > Application Settings > Features to also move every area's Reports group (Identity, Tenant, Security, Intune, Email...) under Reports. Pages keep their addresses.
