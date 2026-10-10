---
description: The rules that rate each computer in the monthly reports as Good, Check or Needs attention.
---

# Device Rules

**Reports > Device Rules** is a table of the rules that rate every computer in the customer reports. A computer gets the worst rating of any rule it meets: Good, **Check** (fine for now, worth a look) or **Needs attention**. The rating shows in the Status column on the *Your Computers* page, and the hardware part of it colours the Hardware column and fills the *Hardware below or close to our minimum* table on *Computer Health*.

Each threshold rule has a **Check when** and a **Needs attention when** value. Leave a box blank to never use that level. Yes/no rules (such as Windows Home) are set to Needs attention, Check or Off. **Reset to defaults** puts every rule back.

| Rule | Default | Notes |
| --- | --- | --- |
| Intel Core processor generation | Needs attention below 8th gen; Check at 8th or 9th gen | Intel Core Ultra and Core 3/5/7 count as 14th gen. |
| AMD Ryzen series | Needs attention below the 3000 series; Check at the 3000 series | 3 = Ryzen 3000 (Ryzen 3 3200G). |
| Physical processor cores | Needs attention below 4; Check at 4 | Physical cores, not threads. |
| Memory fitted | Needs attention below 8 GB; Check at 8 GB | Rounded to the nearest GB. |
| Processor cannot run Windows 11 | Needs attention | Not applied to servers. |
| Entry-level processor | Check | Celeron, Pentium, Atom, Athlon, AMD A-series. |
| Windows no longer gets security updates | Needs attention | |
| Days until Windows security updates end | Check at 90 days or fewer | |
| Windows Home edition | Check | |
| Security updates waiting | Check above 0 | From the RMM's patch scan. |
| Updates failing to install | Check above 0 | Driver updates never count. |
| Drive used | Check above 75% | Any fixed drive over 1 GB. |
| Working days with high memory use | Check above 0 | Days with a memory alert above the threshold, in working hours on a weekday. |
| High memory threshold / working day | 90%, 8am to 6pm | In the reports time zone (Reports > Settings). |
| Days since last seen | Check above 7; Needs attention above 30 | |
| Days without a restart | Check above 30 | |

Changes apply to the next report generated. The device fields used by the Report Builder (HardwareRating, HealthStatus and their notes) update at the next RMM sync.

Changing the rules needs `CIPP.Reports` Read/Write and access to all tenants, because they apply to every company.
