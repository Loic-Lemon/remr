# Agent instructions

## Feature inventory

The Settings → Feature inventory popup is the source users use to track shipped functionality and ideas. Its data lives in `Sources/remr/Core/FeatureInventory.swift` and is rendered by `FeatureInventoryView`.

Whenever a feature is added, removed, renamed, or materially changed, update `FeatureInventory.all` in the same change. Split broad features into separately trackable rows when they have distinct user-visible behavior. Keep each row's name, status, and summary accurate; use `.idea` for candidates that are not shipped. Do not maintain a second hard-coded feature list in the popup view.

## Build & install

After finishing code changes, run `./install.sh` before handing off. It rebuilds, quits the running app, reinstalls to `/Applications/remr.app`, and relaunches. The user tests against `/Applications/remr.app`, so changes are only visible after installing — never leave the source edited and the installed app stale.
