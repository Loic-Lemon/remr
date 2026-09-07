# Changelog

All notable changes to remr are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Calendar view** — a new ⌥⌘C popover with month, week, and day layouts. Reminders appear as chips on their due dates; drag a chip to reschedule (timed reminders keep their time), right-click to snooze, and toggle "Show completed" to reveal completed reminders struck through. "Show Gantt bars" draws continuous, lane-aligned bars from today to each due date (red when overdue) across the month and week grids; the checkbox stays available while switching calendar views.
- **Reminder detail page** — double-click any reminder (or a calendar chip) to open a read-only detail view: title, notes, tags, list, priority, recurrence, created date, and a location map. Edit or open in Reminders from the footer.
- **Ongoing reminders** — mark any incomplete reminder as ongoing from its context menu; ongoing reminders pin to a dedicated section ahead of the chronological buckets without changing their due date.
- **Feature inventory** — a Settings popup tracking every shipped feature and tracked idea, with shipped and idea counts.
- **Menu bar icon badge** — an optional red count badge on the menu bar icon showing overdue or due-today reminders.
- **"This weekend" snooze preset** — snoozes to Saturday at 9 AM (next Saturday once the weekend has passed).
- **Liquid Glass surfaces** — native macOS 26 glass for the popover, controls, fields, and bands, with translucent fallbacks on older macOS.
- **Reminder editor overhaul** — a list-colored header, quick day chips (Today, Tomorrow, …), an always-visible month calendar, time presets plus alarm-clock hour/minute steppers and an AM/PM toggle, an all-day switch, live tag preview, and a discard-changes confirmation.
- **Recurrence indicator** — reminders that repeat (set in Reminders.app) show a ↻ with their schedule.
- **Completion animation** — completing a reminder fills the check circle and draws a checkmark.
- **Search surfaces completed reminders** — completed matches appear under a "Completed" heading and can be restored from there.
- **Popover week calendar** — a compact week strip pinned to the bottom of the main popover, showing each day's active (red) and completed (gray) reminder counts; toggleable from Settings → Calendar.
- **Recently deleted search** — a search field in the Archive popover's "Recently Deleted" tab filters deleted reminders by title, notes, and priority.
- **Detail page actions menu** — the detail page's "…" menu adds snooze presets, Duplicate, Copy Title, Move to List, and Delete.

### Changed

- **Double-click opens the detail page** — double-clicking a reminder now opens the new read-only detail view instead of the editor; Edit and "View in Reminders" are one tap away from there.
- **Thicker menu bar icon outline** — the menu bar glyphs render at medium weight, giving the icon a slightly bolder, more legible stroke.
- **Reminder detail page redesign** — a hero title with a due card (mini week strip, date line, and a relative countdown like "in 3 days" or "2 days overdue"), meta chips for list/priority/recurrence, sectioned Tags/Description/Location, and a pinned "Created" line.
- **Restore button feedback** — restoring a deleted reminder shows a "Restoring…" spinner and disables the button until it completes.
- **All recently deleted reminders shown** — the recovery popover no longer truncates the deleted list at five items.

### Fixed

- **Undo now redoes** — after undoing a completion or deletion, Undo re-applies the original action instead of only reverting once.
- **Vanished selection** — when a selected row leaves the list (completed, deleted, or synced away), the selection moves to the row that took its place instead of leaving a phantom highlight.
- **Appearance consistency** — explicit Light/Dark modes now reach every window and popover, so opacity fills and hairlines resolve identically.
- **Toast animation** — undo and action toasts now rise and fade reliably on macOS, with a content-swap roll when replacing a toast.
- **Search keyboard navigation** — completed and deleted matches follow active matches while searching and are no longer capped at five rows.
- **Click to clear** — clicking empty list space clears the selection.
- **Crisp menu bar icon on low-resolution displays** — the icon is now rasterized at 2× resolution instead of a lazy 1×-scale render, so it stays sharp on Retina and anti-aliased (not pixelated) on non-Retina monitors.
- **Suggestion dropdown** — accepting an `@`/`#`/keyword suggestion closes the dropdown instead of re-proposing the item just inserted.
- **"Later today" snooze** — snoozes to three hours from now instead of a fixed 5 PM, which landed in the past (and immediately overdue) once it's evening.
- **Popover dismissed by sheet clicks** — clicking a confirmation sheet (like "Delete Forever?") no longer closes the popover.
- **Toast rises through the calendar** — the undo/action toast now floats above the bottom week calendar instead of overlapping it.
- **Taller calendar cells** — month cells grow from 56pt to 104pt with vertical scrolling and show four reminders per day instead of three; week columns grow to 300pt, so days fit their items instead of clipping at two.
