---
description: Turn Community Additions add-ons on and off, check them against the CIPP version, and upload or download packages.
---

# Add-ons

**Community Additions > Settings > Add-ons** manages the add-ons installed in this CIPP. You need the **CIPP.AppSettings** permission (read to look, read/write to change anything).

## What an add-on is

An add-on is a Community Addition packaged so it can be added to, checked against and removed from CIPP in a standard way. Its parts sit in their own folders, named after the add-on's id:

| Part | In the CIPP code | In a package |
| --- | --- | --- |
| Manifest (`addon.json`) | `backend/Config/Addons/<id>/addon.json` | `addon.json` |
| Backend functions | `backend/Modules/CIPPCore/Public/Addons/<id>` | `backend/functions` |
| API endpoints | `backend/Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Addons/<id>` | `backend/endpoints` |
| Settings files | `backend/Config/Addons/<id>` | `backend/config` |
| Backend tests | `backend/Tests/Addons/<id>` | `backend/tests` |
| Page components | `frontend/src/addons/<id>` | `frontend/components` |
| Pages | `frontend/src/pages/addons/<id>` (URL `/addons/<id>`) | `frontend/pages` |
| Frontend tests | `frontend/tests/addons/<id>` | `frontend/tests` |
| Documentation | `docs/user-documentation/addons/<id>` | `docs` |

`backend/Config/AddonLayout.json` defines this layout, the file types each part may contain and the package size limits.

The manifest says:

* `id`, `name`, `version`, `description`, `author`, `category`;
* `cipp.minVersion` and `cipp.testedWith`: the oldest CIPP it works with, and the CIPP versions it has been tested on;
* `menu`: its pages, with the permissions needed to see them and where they go in the menu (`placement`);
* `endpoints`: its API endpoints;
* `dependsOn`: what it uses from CIPP itself (functions and frontend files), kept up to date by `Update-CippAddonDependencies.ps1` and checked by the tests;
* `coreChanges`: changes it needed to CIPP's own files, which can conflict when CIPP is updated;
* `storage`: tables it keeps data in.

## The page

### This CIPP's version

The top of the page shows this CIPP's version and the newest CIPP version, so you can see when an update is out that the add-ons haven't been checked against.

### Installed add-ons

Each installed add-on shows:

* **On/off**: a turned-off add-on's pages leave the menu and its API endpoints are refused. Nothing is deleted, and turning it back on restores it. (Each add-on has a feature flag, `Addon.<id>`, which isn't listed in **CIPP > Settings > Features**.)
* **Compatibility** with this CIPP:

  | Status | Meaning |
  | --- | --- |
  | Compatible | Tested on this CIPP version (major.minor) and everything it uses is present. |
  | Not tested on this version | Everything it uses is present, but nobody has recorded testing it on this version yet. Check it, then add the version to `cipp.testedWith`. |
  | Needs a newer CIPP | This CIPP is older than the add-on's `cipp.minVersion`. |
  | Problem | A CIPP function it uses is missing (removed or renamed in CIPP), one of its endpoints didn't load, or its manifest is invalid. The missing names are listed. |

* whether it has been tested on the newest CIPP version;
* where it sits in the menu, and where it could later move to;
* any changes it made to CIPP's own files, and the tables it keeps data in;
* **Open** and **Download package**. Packages of the installed add-ons are made when the CIPP image is built.

### Uploaded packages

**Upload package (.zip)** checks an add-on package and keeps it in this CIPP so it can be downloaded later, for example to install it into the code. Uploading doesn't install or run anything. A package is refused if:

* it is larger than 10 MB, or has more than 500 files, or any file is larger than 5 MB;
* a path in it isn't a plain relative path (for example contains `..`), or a file isn't in one of the add-on folders, or is a type that folder doesn't allow;
* `addon.json` is missing or invalid;
* an endpoint listed in `addon.json` has no file, or an endpoint file isn't listed;
* a backend script doesn't parse, doesn't define exactly the one function it is named after, or has code outside that function;
* a menu entry has no page;
* a file doesn't match `checksums.json` (it was changed after packaging);
* a function in it has the same name as one already in CIPP.

Each upload shows its compatibility with this CIPP, whether it is new, newer, the same as or older than the installed version, its warnings (for example no tests or no documentation) and its SHA-256.

## Installing and removing add-ons

Add-ons are part of the CIPP code, so they go through the same review, tests and build as the rest of it. From a copy of the CIPP repository, using PowerShell 7:

| Task | Command |
| --- | --- |
| Install | `build/tools/addons/Install-CippAddon.ps1 -Path <package.zip>` |
| Upgrade | `build/tools/addons/Install-CippAddon.ps1 -Path <package.zip> -Upgrade` |
| Remove | `build/tools/addons/Uninstall-CippAddon.ps1 -Id <id>` |
| Make a package | `build/tools/addons/Export-CippAddon.ps1 -Id <id>` (or `-All`) |
| Update `dependsOn` after changing an add-on | `build/tools/addons/Update-CippAddonDependencies.ps1 -Id <id>` |

Install checks the package the same way as an upload, refuses one that is already installed (unless `-Upgrade`) or whose functions clash with CIPP's, and copies each part to its folder. Remove deletes the add-on's folders but leaves the data it stored. Neither commits anything: run the tests, review the changes, then commit and push, and the add-on appears (or goes) once the new image is running.

## Before updating CIPP

When a new CIPP version is out, check the add-ons against it before merging it:

```
git fetch upstream --tags
pwsh build/tools/addons/Test-CippAddonUpstream.ps1 -Ref upstream/main
```

For each add-on it lists:

* **BREAK**: a CIPP function or frontend file it uses is gone, a function it calls lost a parameter, or the new CIPP has a function, endpoint or page with the same name as the add-on's;
* **REVIEW**: a CIPP function or frontend file it uses changed (with whether the function's parameters changed), or a CIPP file the add-on changed was changed too (expect a merge conflict);
* whether the add-on has been tested on the new version.

After merging, the add-on tests (`backend/Tests/Addons`) fail until each add-on lists the new version in `cipp.testedWith`, so recording that it has been checked is part of the update.

## Where add-ons appear in the menu

An add-on's pages always have URLs under `/addons/<id>`, wherever they appear in the menu. Each menu entry has a `placement`: **Community Additions** for now. It can name another part of the menu instead (for example `Tenant Administration > Applications`); if that place no longer exists, the entry falls back to Community Additions. `preferredPlacement` records where an add-on would fit best, for when add-ons move out of Community Additions. Because the URL doesn't change, moving an add-on doesn't break links or bookmarks.
