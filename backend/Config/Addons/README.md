# Community Additions add-ons

One folder per installed add-on, named after its id, holding its `addon.json` manifest and any settings
files it reads at runtime. The rest of an add-on lives in the folders listed in `../AddonLayout.json`.

Install, remove and package add-ons with the scripts in `build/tools/addons`; see
`docs/user-documentation/community/settings/addons.md`. This file keeps the folder in place when no
add-ons are installed (the frontend build reads the manifests from here).
