# Companies

Every tenant in CIPP is listed as a reporting company.

| Setting | Meaning |
| --- | --- |
| Produce monthly reports | Reporting on or off for the company. Bulk actions turn several on or off at once. |
| Customer report recipients | Who receives the customer report. Nothing is sent to customers while **Allow sending reports to customer recipients** is off in [Settings](settings.md). |
| Pre-check recipients | Overrides the default pre-check address for this company. |
| Delivery | Default, Review then send, Send automatically, or Manual only. |
| Schedule | Default, a custom day of the month, Manual only (Test button), or Paused until a date. |
| Report covers | Default (from [Settings](settings.md)), the previous calendar month, one month up to yesterday, or the last 30 days. For a report on the 15th, "one month up to yesterday" covers the 15th of last month to the 14th. |
| Report sections | The sections of this company's report, top to bottom. Drag the handle (or use the arrows) to reorder. Leave empty to use the default sections. **Set report sections** sets several companies at once. |
| Internal notes | For your team; never shown to the customer. |

The table also shows the company's RMM customer (from the integration's tenant mapping) and a data status, so missing mappings or Microsoft 365 connection errors are visible before reports run.

## Actions

* **Edit report settings** - the settings above.
* **Create draft for review** - make the customer report as a draft to check and send from [Review](review.md). Nothing is emailed.
* **Test customer report** / **Test pre-check** - generate now and send only to the address you type.

For drafts and tests, choose the period:

* **Company's usual period** (also used when you leave it blank) - whatever **Report covers** says.
* **Previous calendar month**, **One month up to yesterday**, **This month so far**.
* **Last 7 / 30 / 90 days** - whole days up to the end of yesterday.
* **Custom dates** - pick the first and last day (both included, up to 366 days).
* Or type a month as YYYY-MM.

A report that covers a month (a calendar month, one month up to yesterday, or 28-31 days) is the **Monthly IT Report**. A shorter or longer period is called the **IT Report**, and its wording says "this period" rather than "this month". Dates are whole days in UTC. Older periods only include what CIPP still holds from the RMM and Microsoft 365.
* **Set report sections** - for one or many companies.
* **Turn reporting on / off**.
