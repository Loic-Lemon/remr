# remr

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-9cf)](#requirements)
[![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange)](Package.swift)

A keyboard-first Reminders companion for your macOS menu bar.

Type plain English — `pick up dry cleaning tomorrow at 5pm @errands` — and remr turns it into a real reminder, synced both ways with the Reminders app.

## Features

- **Natural-language input** — `tomorrow at 5pm`, `@home`, `#groceries`, `&the office` become real reminder fields
- **Quick Add** — ⌥⌘N opens a composer from anywhere
- **Reminder detail page** — double-click a reminder for the full picture (notes, tags, list, priority, recurrence, location on a map), then edit or open in Reminders
- **Calendar view** — ⌥⌘C: month, week, and day layouts; drag to reschedule, right-click to snooze
- **Editing, bulk create, snooze, tag manager** — power-user tooling, all keyboard-first
- **Ongoing reminders** — pin reminders to a dedicated section without changing their due date
- **Search & tags** — `@work`, `#urgent`, `!!`, or the tag dropdown; completed reminders are searchable too
- **Archive** — restore completed or deleted reminders
- **Appearance & icon** — Light/Dark/System, plus a customizable menu bar symbol, color, and overdue/due-today badge

## Install

```bash
git clone https://github.com/Loic-Lemon/remr.git
cd remr
swift build
Scripts/make-bundle.sh
```

Copy `build/Build/Products/Debug/remr.app` to `/Applications` and grant Reminders access on first launch.

> Use the `.app` — the bare binary can't access your reminders.

## Requirements

macOS 13 or later · Xcode or Command Line Tools · no third-party dependencies
