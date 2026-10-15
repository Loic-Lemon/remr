![remr — project banner](assets/readme-banner.svg)

# remr

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-9cf)](#requirements)
[![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange)](Package.swift)
[![Two-way Reminders sync](https://img.shields.io/badge/Reminders-two--way_sync-2E7D32)](#features)
[![Local AI: optional](https://img.shields.io/badge/Local_AI-Ollama_optional-7C3AED)](#optional-local-model-features)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](#)

**A keyboard-first Reminders companion for your macOS menu bar.**

Type plain English — `pick up dry cleaning tomorrow at 5pm @errands` — and remr
turns it into a real reminder, synced both ways with the Reminders app. Everything
lives in the notch, one keystroke away, and the whole thing runs locally.

> [!TIP]
> ### ✨ Bulk Markdown → Reminders
> Paste a whole Markdown plan into remr. Headings become tags, and a local Qwen
> model interprets each item into a clean title, description, and deadline. Review
> everything before anything is created.

<https://github.com/user-attachments/assets/09ed40d6-ada5-4551-8618-8e6bea71c3eb>

> [!NOTE]
> ### 🆕 What's new
>
> - **Little sun review nudges** — every 90–180 minutes the notch quietly grows two
>   slim wings: a smiling sun waves on the left, a review action waits on the right.
>   It retracts after 18 seconds, never steals keyboard focus, and respects Reduce Motion.
> - **⌥Space opens remr** — a simpler default global shortcut, still rebindable in
>   Settings → Shortcuts.
> - **Calendar in the notch** — `⌥⌘C` opens the calendar from the top screen edge with a
>   prewarmed 220 ms reveal, and `C` flips between reminders and calendar in place.
> - **Calmer glass** — sharper text fields, clearer glass, a shorter opening motion,
>   and a retracting close matched to the camera housing.
> - **Tidier Settings** — four compact tabs with immediate changes and a persistent
>   shortcut save bar.
> - **Rounded dropdowns** — lists, tags, snooze, and colors share one glass card style
>   with keyboard navigation.
> - **Raycast companion** — a new **Agenda** command in `raycast-extension/`.

## Contents

- [Features](#features)
  - [Capture](#-capture) · [Organize](#-organize) · [Plan](#-plan) · [Focus](#-focus) · [Local AI](#-local-ai-optional) · [Make it yours](#-make-it-yours)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Install remr](#install-remr)
- [Optional: local model features](#optional-local-model-features)
- [Bulk Markdown import](#bulk-markdown-import)
- [Raycast extension](#raycast-extension)
- [Privacy](#privacy)
- [Development](#development)
- [Requirements](#requirements)

## Features

### ⚡ Capture

- **Natural-language input** — `tomorrow at 5pm`, `@home`, `#groceries`, `&the office`
  become real reminder fields. remr understands relative dates, clock times,
  all-day values, priority phrases, and rollover for times that have passed.
- **Quick Add** — `⌥⌘N` opens a focused composer from anywhere, no need to open the
  full panel first.
- **Live parse preview** — colored chips show the title, list, tags, priority, and
  date as you type, with non-blocking diagnostics when something looks off.
- **Voice capture** — dictate a reminder, clean the transcript locally, and drop it
  straight into the composer.
- **Bulk Markdown import** — paste headings and bullets, let a local model clean up
  each item, review the results, then create only the rows you select.
- **macOS Services** — select text in any app and choose **Create Reminders** from
  the Services menu.

### 🗂 Organize

- **Ongoing reminders** — pin incomplete reminders to a dedicated section ahead of
  the chronological buckets, without changing their due date.
- **Search & tags** — search reminder text, `@lists`, `#tags`, and priority markers.
  Completed reminders are searchable too, and a tag dropdown filters the list in place.
- **Smart Search** — optional, local embedding search that ranks related reminders by
  meaning, not just substring match.
- **Tag manager** — rename, recolor, and remove tags across every reminder from one view.
- **List visibility picker** — a searchable list dropdown with live counts and a
  one-click "Show all".
- **Archive & recovery** — browse completed and recently deleted reminders, filter
  them, and restore with safeguards.
- **Undo safety net** — reverse the latest completion or deletion from the toast or
  with `⌘Z`.

### 📅 Plan

- **Calendar view** — `C` toggles between reminders and the calendar inside remr, and
  `⌥⌘C` opens it from anywhere. Month, week, and day layouts open from the notch with a
  prewarmed 220 ms reveal. Drag a chip to reschedule, right-click to snooze, and toggle
  "Show completed" to reveal finished items struck through.
- **Gantt timeline** — continuous, lane-aligned bars run from today to each due date
  (red when overdue) across the month and week grids.
- **Free-day shading** — days with nothing planned are striped with a faint diagonal,
  so open time reads at a glance.
- **Reminder detail page** — double-click any reminder (or calendar chip) for the full
  picture: notes, tags, list, priority, recurrence, a location map, and a due-date
  countdown like "in 3 days" or "2 days overdue" — plus one-tap snooze, duplicate,
  copy-title, move-to-list, and delete.
- **Popover week strip** — an at-a-glance week pinned to the bottom of the menu bar
  panel with per-day active and completed counts (toggle in Settings → Workspace).
- **Snooze that fits** — presets for one hour, later today, tomorrow, next Monday, and
  "This weekend" (Saturday 9 AM), plus a custom date/time picker and clear-due-date.

### 🍅 Focus

- **Pomodoro timer** — run focus and short-break sessions from the menu bar with
  adjustable durations. Press `P` to show or hide it.
- **Little sun review nudges** — the notch widens into two slim wings with a smiling
  sun waving on the left and a review action on the right. It appears at a random
  interval between 90 minutes and 3 hours, retracts after 18 seconds, never steals
  keyboard focus, and respects Reduce Motion. Click it to review, or preview and
  customize the range in Settings → Workspace → Review nudges.

### 🧠 Local AI (optional)

Off by default. Enable **Settings → Intelligence → Local model → Enable local model
features** to unlock:

- **Bulk Markdown cleanup** — a local Qwen model rewrites each item into a clean title,
  description, and deadline.
- **Voice cleanup** — dictated text is tidied locally before it becomes a reminder.
- **Smart Search** — reminders are embedded once, cached in memory, and compared
  against your query on-device.
- **Usage stats** — average request time, active time, battery usage, cache hits, and
  errors, shown only in aggregate and only locally.

### 🎨 Make it yours

- **Appearance** — Light, Dark, or Follow System, applied live to every window and popover.
- **Menu bar icon** — choose the glyph (the fuller checklist is the default), its color,
  and an optional overdue/due-today count badge.
- **Notch panel** — resize the top-centered panel from 400 to 900 points, with an
  optional gentle opening haptic on compatible trackpads.
- **Shortcuts** — every global hotkey and in-app key is rebindable, with conflict
  reporting and validation.

## Keyboard shortcuts

Global shortcuts work from anywhere; in-app shortcuts work while remr is open.
Everything below is rebindable in **Settings → Shortcuts**.

| Action | Default |
| --- | --- |
| Open remr | `⌥Space` |
| Quick add reminder | `⌥⌘N` |
| Open calendar view | `⌥⌘C` |
| Voice verify | `⌥⌘V` |
| Voice log | `⌥⇧⌘V` |
| Switch reminders / calendar | `C` |
| Show / hide Pomodoro | `P` |
| Focus search | `⌘F` |
| Move selection | `↑` `↓` |
| Move a page | `PageUp` `PageDown` |
| Scroll | `Space` / `⇧Space` |
| Open recovery | `←` |
| Complete / restore row | `Return` |
| Open in Reminders | `⌘Return` |
| Edit selected reminder | `E` |
| Snooze selected reminder | `S` |
| Delete row | `⌫` |
| Undo last action | `⌘Z` |
| Close panel | `Esc` |

## Install remr

Install the standard reminder features. This setup does **not** require Ollama.

```bash
git clone https://github.com/Loic-Lemon/remr.git
cd remr
./install.sh
```

The installer builds an optimized release app, copies it to `/Applications/remr.app`,
and launches it. Grant Reminders access on first launch. Pass `--no-launch` to build and
install without relaunching.

> [!IMPORTANT]
> Use the installed `.app`. The bare binary cannot access your reminders.

> [!NOTE]
> remr is menu-bar only and writes each reminder to Reminders.app as it's created.
> Quitting and reinstalling is safe — nothing is lost.

## Optional: local model features

Enable **Settings → Intelligence → Local model → Enable local model features** to use
Bulk Markdown import, voice cleanup, and Smart Search. The same section lists installed
models and suggests recommended ones with their install commands.

Install [Ollama](https://ollama.com/download/mac), or use Homebrew:

```bash
brew install ollama
ollama pull qwen2.5:3b
ollama pull nomic-embed-text
```

- **Generation models** (bulk cleanup, voice cleanup): `qwen2.5:3b` is the balanced
  default, `qwen2.5:1.5b` is lighter and faster, and `llama3.2:3b` trades quality for speed.
- **Embedding model** (Smart Search): `nomic-embed-text`, selected separately under
  **Embedding model** in Settings.

> [!TIP]
> remr starts Ollama on demand and stops only the process it started. If Ollama was
> already running, remr leaves it alone.

## Bulk Markdown import

1. Click the bulk-import button in the remr toolbar.
2. Paste Markdown with headings and list items.
3. Click **Interpret**.
4. Review and edit the reminder preview.
5. Click **Create Selected**.

Example:

```markdown
# bobs burgers
## patties

1. Investigate whether the cooking time equals the cutting time
   - Compare the beef and onions separately
   - Document the result by next Friday

2. Buy ingredients
   - Beef
   - Onions
```

Each numbered item becomes one reminder. Bullets beneath a number become that
reminder's description, even when they contain action phrases. Headings become tags
like `#bobs-burgers` and `#patties`. Qwen cleans the title and description and
normalizes the deadline wording; remr resolves the final date.

## Raycast extension

The `raycast-extension/` folder adds a Raycast command, **Agenda**, that opens remr's
calendar from Raycast through the `remr://calendar` URL scheme. remr must be installed
(`./install.sh`) for the scheme to resolve; the extension itself is a thin launcher and
does not read Reminders directly. See
[`raycast-extension/README.md`](raycast-extension/README.md) to develop it locally.

## Privacy

> [!NOTE]
> remr is built to keep your data on your Mac.
>
> - **Reminders** stay in Apple's Reminders app; remr only reads and writes through EventKit.
> - **Location** is used only when you add a location to a reminder — never stored, logged,
>   shared, or tracked in the background.
> - **Microphone and speech** are used only when you explicitly start dictation, with
>   on-device recognition.
> - **Local models** run through Ollama on your machine. Nothing is sent to a cloud service.

## Development

```bash
swift build -c release    # build
./install.sh              # build, install to /Applications, and relaunch
swift test                # XCTest suite (needs a full Xcode toolchain)
```

With only Command Line Tools installed, `swift test` can't compile the XCTest suite
(no `XCTest.framework`). Use the harness scripts instead:

```bash
Scripts/parser-check.sh          # natural-language parser cases
Scripts/review-nudge-check.sh    # review nudge scheduling
Scripts/notch-calendar-check.sh  # calendar layout
Scripts/dropdown-check.sh        # dropdown geometry
Scripts/morph-check.sh           # panel morph animation
```

> [!IMPORTANT]
> The Settings → Feature inventory popup is the source of truth for shipped and
> planned functionality (`Sources/remr/Core/FeatureInventory.swift`). Update it in the
> same change as any feature addition or removal.

## Requirements

macOS 13 or later · Xcode or Command Line Tools · no third-party Swift dependencies

---

Built by [Loic Lemon](https://github.com/Loic-Lemon). Not affiliated with Apple.
