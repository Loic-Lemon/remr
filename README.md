# remr

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-9cf)](#requirements)
[![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange)](Package.swift)

A keyboard-first Reminders companion for your macOS menu bar.

Type plain English — `pick up dry cleaning tomorrow at 5pm @errands` — and remr turns it into a real reminder, synced both ways with the Reminders app.

> [!TIP]
>
> ## ✨ Bulk Markdown → Reminders
>
> Paste a whole Markdown plan into remr. Headings become tags, and local Qwen interprets each item into a clean title, description, and deadline. Review everything before creation.

<https://github.com/user-attachments/assets/09ed40d6-ada5-4551-8618-8e6bea71c3eb>

## Features

- **Natural-language input** — `tomorrow at 5pm`, `@home`, `#groceries`, `&the office` become real reminder fields
- **Quick Add** — ⌥⌘N opens a composer from anywhere
- **Reminder detail page** — double-click a reminder for the full picture: notes, tags, list, priority, recurrence, location on a map, and a due-date countdown — plus one-tap snooze, duplicate, copy-title, move-to-list, and delete actions
- **Calendar view** — ⌥⌘C: month, week, and day layouts; drag to reschedule, right-click to snooze; optional Gantt bars from today to each due date in the calendar footer; plus an at-a-glance week strip pinned to the popover (toggle in Settings)
- **Bulk Markdown import** — paste headings and bullets, let local Qwen clean up each reminder, review the results, then create selected items
- **Editing, bulk create, snooze, tag manager** — power-user tooling, all keyboard-first
- **Ongoing reminders** — pin reminders to a dedicated section without changing their due date
- **Search & tags** — `@work`, `#urgent`, `!!`, or the tag dropdown; completed reminders are searchable too
- **Archive** — restore completed or deleted reminders
- **Appearance & icon** — Light/Dark/System, plus a customizable menu bar symbol (the fuller checklist glyph is the default), color, and overdue/due-today badge

## Install remr

Install the standard reminder features. This setup does not require Ollama.

```bash
git clone https://github.com/Loic-Lemon/remr.git
cd remr
./install.sh
```

The installer builds the app, copies it to `/Applications/remr.app`, and launches it. Grant Reminders access on first launch.

> Use the `.app`. The bare binary cannot access your reminders.

## Optional: Local model features

Enable **Settings → Local Model → Enable local model features** to use Bulk Markdown import.

Install Ollama from [ollama.com](https://ollama.com/download/mac), or use Homebrew:

```bash
brew install ollama
ollama pull qwen2.5:3b
```

Remr starts Ollama when it needs to parse a bulk import. It stops only the Ollama process that it started. If Ollama was already running, remr leaves it running.

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

- Does the cooking time equal the cutting time? Cook and cut the beef and onions. Due next week Friday.
```

Headings become tags such as `#bobs-burgers` and `#patties`. Qwen cleans the title and description and normalizes the deadline wording. Remr resolves the final date.

## Requirements

macOS 13 or later · Xcode or Command Line Tools · no third-party Swift dependencies
