# remr

[![macOS](https://img.shields.io/badge/macOS-13%2B-9cf)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5.10-orange)](Package.swift)

A keyboard-first Reminders companion for your macOS menu bar.

Type a reminder in plain English — `pick up dry cleaning tomorrow at 5pm @errands` — and remr turns it into a real reminder, in sync with the Reminders app both ways.

## Features

- **Plain-English input** — `tomorrow at 5pm`, `@home`, `#groceries`, `at the office` become real reminder fields
- **Quick Add** — global shortcut (⌥⌘N) opens a compact composer from anywhere; no need to switch apps
- **Reminder Editing** — open any reminder inline to change title, notes, due date, priority, list, location, or tags
- **Bulk Reminder Creation** — paste multiple lines; preview each parsed reminder; create all, select a subset, or retry only the failed ones
- **Tag Manager** — rename, recolor, or remove tags across every reminder with one click
- **Snooze Menu** — one-click snooze with smart presets: 1 hour, later today, tomorrow morning, tomorrow evening, next Monday
- **Keyboard-first** — arrows, Enter, ⌘Enter, ⌫, Tab, Esc — everything from the keyboard
- **Customizable Shortcuts** — rebind any action (⌘,), including the global shortcuts ⌥⌘R (open remr) and ⌥⌘N (quick add)
- **Appearance Modes** — Light, Dark, or Follow System
- **Parse Preview** — live parsing feedback as you type; diagnostics show warnings before you create
- **One Popover** — overdue, today, this week, next week, this month, next month, and future, no Dock icon needed
- **Search & Tags** — filter with `@work`, `#urgent`, `!!`, the tag dropdown (with its own search box), or a `#tag` chip
- **Safety Net** — completed and deleted reminders can be restored from the Archive
- **Fast Popover** — optimized presentation, glass-backed surfaces, no flicker

## Install

```bash
git clone https://github.com/Loic-Lemon/remr.git
cd remr
swift build
Scripts/make-bundle.sh
```

Copy `build/Build/Products/Debug/remr.app` to `/Applications` and grant Reminders access on first launch.

> Use the `.app` — the bare binary (`swift run remr`) is unsigned and can't access your reminders.

## Quick Reference

**Typing a reminder** — a few examples:

| You type | What happens |
|---|---|
| `tomorrow at 5pm` | Due tomorrow at 5 PM |
| `@home` · `#groceries` · `at the office` | List, tag, or location |
| `high priority` | Priority (`p1`–`p3`, `low` too) |

**The list** — click a row to select it (highlighted); click again to open in Reminders. Arrows move the selection, Enter completes, ⌘Enter opens in Reminders, ⌫ deletes. Right-click supports moving, duplicating, and copying a title. Completed and deleted reminders are available from the Archive icon.

**Quick Add (⌥⌘N)** — type, see live parse preview, press Enter to create. Esc cancels.

**Editing a reminder** — double-click or right-click → Edit. Change any field; Save writes back to Reminders.app.

**Bulk Add** — click the bulk button (or paste multiple lines), review the preview, toggle rows, Create Selected or Retry Failed.

**Search** — `@work`, `#urgent`, `!!`, or any text; use the tag dropdown (right of the search box, with its own search) or click a `#tag` chip to filter by tag. Open the tag picker's gear to rename, recolor, or remove tags.

**Snooze** — right-click a reminder → Snooze; pick a preset. The due date shifts, priority and list stay intact.

**Sync** — the footer shows a friendly update status such as "Updated moments ago" or "Updated today."

**Settings (⌘,)** — rebind any shortcut; both global shortcuts (⌥⌘R to open remr and ⌥⌘N to quick add) are editable there. Choose Light/Dark/System appearance.

**Also** — Enter adds notes (Shift+Enter = new line) · select text in any app → Services → Create Reminders · right-click the menu bar icon to Refresh or Quit.

A date without a time is all-day; a time that already passed rolls to tomorrow.

## Requirements

macOS 13 or later · Xcode or Command Line Tools to build · no third-party dependencies

## Development

- `swift test` — unit tests (needs full Xcode)
- `Scripts/parser-check.sh` — parser harness (Command Line Tools only)
- Parsers: `Sources/remr/Core/Parser/` · EventKit: `Sources/remr/Core/ReminderStore.swift`

---

<p align="center"><sub>Built with <a href="https://www.deepseek.com/">DeepSeek V4 Flash</a> via <a href="https://opencode.ai/go">opencode go</a> on <a href="https://github.com/can1357/oh-my-pi">Oh My Pi</a></sub></p>
