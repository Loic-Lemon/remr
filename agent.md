# Agent instructions

## Feature inventory

The Settings → Feature inventory popup is the source users use to track shipped functionality and ideas. Its data lives in `Sources/remr/Core/FeatureInventory.swift` and is rendered by `FeatureInventoryView`.

Whenever a feature is added, removed, renamed, or materially changed, update `FeatureInventory.all` in the same change. Split broad features into separately trackable rows when they have distinct user-visible behavior. Keep each row's name, status, and summary accurate; use `.idea` for candidates that are not shipped. Do not maintain a second hard-coded feature list in the popup view.

## Build & relaunch

After every prompt is fully finished, run `./install.sh` before handing off, even when the prompt only changes existing code. It rebuilds, quits the running app, reinstalls to `/Applications/remr.app`, and relaunches. The user tests against `/Applications/remr.app`, so never leave source edits without rebuilding and relaunching the installed app.
