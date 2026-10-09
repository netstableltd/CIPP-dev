# Atera

Atera is an RMM and PSA. The integration copies each mapped customer's devices, alerts, tickets, contracts and purchases into CIPP's Reporting DB every night, where the [Reports](../../reports/README.md) area and the [Report Builder](../../tools/report-builder/README.md) can use them.

## Set up

1. In Atera, create an API key (Admin > API). A read-only key is enough. To include **purchases**, the key must also be able to read billing/invoices; without it, everything else still syncs.
2. In CIPP, go to **CIPP > Integrations > Atera**, enable the integration, paste the key and save. The key is stored in Key Vault. Use **Test** to check it.
3. On the **Tenant Mapping** tab, click **Automap** (matches on the Atera customer's domain, then on name; ambiguous matches are skipped and existing mappings are never changed). Check and adjust the result, then save.
4. Click **Force Sync** for a first sync, or wait for the nightly run (between 00:00 and 06:00 UTC).

## What is synced

| Collection | Contents |
| --- | --- |
| AteraCustomer | The Atera customer record |
| AteraAgents | Every device, with the insights below |
| AteraAlerts | Alerts from the last 90 days |
| AteraTickets | Tickets from the last 45 days, plus every open or pending ticket. `TimeLoggedMinutes` is added (Atera leaves `TotalDurationMinutes` at 0) |
| AteraContracts | Every contract |
| AteraPurchases | Product, product/service and expense lines from invoices in the last 400 days, matched on the customer's name |

The sync is account-wide (about 70-100 API calls a night), because Atera's alert and invoice endpoints cannot be filtered by customer.

## Device insights

Each device gets plain-English verdicts that the reports use and that the Report Builder can show, filter or chart:

| Field | Meaning |
| --- | --- |
| UpdateStatus | **Up to date**, **Behind** or **Unknown**. Compares the device's Windows build revision with the newest revision that is common (2+ devices and 10%) among recently seen devices on the same build across the whole Atera account. |
| WindowsVersion, WindowsSupport, WindowsSupportEnds | The Windows version, and whether it still receives security fixes (Supported / Ending soon within 90 days / Unsupported), by build and edition, from `Config/WindowsLifecycle.json`. Update that file as Microsoft releases new versions. |
| HardwareTier, HardwareNotes | **Good**, **Limited** or **Weak**. Weak: 4 GB RAM or less, 2 cores or fewer, a CPU too old for Windows 11 or about 10+ years old, or two lesser limits together (8 GB RAM, an entry-level CPU, a CPU about 7+ years old). |
| CpuSummary, CpuYear, Windows11Ready, MemoryGB | The processor family and generation, its approximate launch year, and whether it can run Windows 11. |
| SystemDiskFreePercent, DaysSinceSeen, DaysSinceReboot | Disk space and ages. |
| ResourceAlertDays, DiskAlertDays, AlertCount | Days with CPU/memory or disk alerts in the last 90 days, and the total alerts. 5+ resource alert days marks a device as regularly overloaded. |
| IsHomeEdition | Windows Home, which cannot be managed like Pro. |
| HealthStatus, HealthNotes | **Good**, **Check** or **Needs attention**, with the reasons. |

The Report Builder's **Pre-built** list has Atera devices, alerts, tickets, contracts and purchases blocks built on these.
