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
| AteraAgents | Every device, with the insights below, including its patch scan (Atera's installed and available updates; two API calls per device of a mapped customer) |
| AteraAlerts | Alerts from the last 90 days |
| AteraTickets | Tickets from the last 45 days, plus every open or pending ticket. `TimeLoggedMinutes` is added (Atera leaves `TotalDurationMinutes` at 0) |
| AteraContracts | Every contract |
| AteraPurchases | Product, product/service and expense lines from invoices in the last 400 days, matched on the customer's name |

The sync is account-wide (about 70-100 API calls a night), because Atera's alert and invoice endpoints cannot be filtered by customer.

## Device insights

Each device gets plain-English verdicts that the reports use and that the Report Builder can show, filter or chart:

| Field | Meaning |
| --- | --- |
| UpdateStatus | **Up to date**, **Behind** (security updates waiting), **Failing** (a security update failed to install) or **Unknown**, from Atera's patch scan. Devices without a scan are compared with the Windows build 40% of recently seen devices in the account have reached. |
| SecurityUpdatesWaiting, UpdatesWaiting, DriversWaiting, UpdatesFailing, LastSecurityUpdate, PatchScanDate | The patch scan: updates still to install (drivers listed separately as optional; antivirus definitions ignored), failures, and the date of the last security update. |
| WindowsVersion, WindowsSupport, WindowsSupportEnds | The Windows version, and whether it still receives security fixes (Supported / Ending soon within 90 days / Unsupported), by build and edition, from `Config/WindowsLifecycle.json`. Update that file as Microsoft releases new versions. |
| HardwareRating, HardwareNotes, CpuGeneration | **Good**, **Check** or **Needs attention** from the hardware rules in [Reports > Device Rules](../../reports/device-rules.md) (processor generation, cores, memory, Windows 11 support), with the reasons. HardwareTier says the same as Meets baseline / Borderline / Below baseline. |
| CpuSummary, CpuYear, Windows11Ready, MemoryGB | The processor family and generation, its approximate launch year, and whether it can run Windows 11. |
| Drives, DrivesOver75, DrivesOver90, FullestDrivePercent | How full every drive is (duplicates and partitions under 1 GB ignored). DrivesOver75 lists drives over the Drive used threshold in the Device Rules (75% by default). |
| MemoryHighDays, MemoryPeakPercent, MemoryTopProcess | Weekdays (08:00-18:00 in the Reports time zone) with a memory alert above 90%, the highest reading and the process using most memory - a nudge to add RAM. |
| SystemDiskFreePercent, DaysSinceSeen, DaysSinceReboot | Disk space and ages. |
| ResourceAlertDays, DiskAlertDays, AlertCount | Days with CPU/memory or disk alerts in the last 90 days, and the total alerts. |
| IsHomeEdition | Windows Home, which cannot be managed like Pro. |
| HealthStatus, HealthNotes | **Good**, **Check** or **Needs attention**, with the reasons: the worst of every rule in [Reports > Device Rules](../../reports/device-rules.md). |

The Report Builder's **Pre-built** list has Atera devices, alerts, tickets, contracts and purchases blocks built on these.
