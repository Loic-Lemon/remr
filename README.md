# remr

A keyboard-first Reminders companion that lives in your menu bar.

remr puts a checklist icon in the macOS menu bar. Click it, type a reminder
in plain English — `pick up dry cleaning tomorrow at 5pm @errands` — and the
due date, list, priority, tags, and location are parsed out of the line as
you type. Everything stays in sync with the Reminders app in both directions.

## Features

- **Natural-language capture** — `tomorrow at 5pm`, `@home`, `high priority`, `at the office`: each becomes a real reminder field.
- **Keyword autocomplete** — start typing a date or priority and press Tab to complete it.
- **Quick description** — a notes box appears as you type; Enter creates, Shift+Enter adds a line.
- **Overdue / Today / Later** — the whole list in one popover, no Dock icon needed.
- **Keyboard-first** — arrows move the selection, Enter completes, ⌘Enter opens in Reminders, ⌫ deletes, Tab hops title → notes → search → list, Esc steps back.
- **Customizable shortcuts** — every shortcut is rebindable in Settings (gear icon or ⌘,), including the global hotkey that opens remr from anywhere (⌥⌘R by default).
- **Search** — filter by list (`@work`), tag (`#urgent`), priority (`!!`), or any text, all combinable.
- **Tag filtering** — click any `#tag` chip to show only reminders with that tag; click it again (or the ✕) to clear. The filter sticks across launches until you change it.
- **Tags** — `#groceries` gets a colored chip; right-click a chip to recolor it.
- **Recently Completed & Recently Deleted** — mistakes are recoverable: deleted reminders can be restored.
- **Location reminders** — `at the office` attaches a geofenced alarm.
- **macOS Service** — select text anywhere, then *Services → Create Reminders*: the first line becomes the title, the rest the description.
- **Always in sync** — Reminders.app changes appear automatically (30-second refresh plus live change notifications).

## Natural language

Type a line and press Enter. The title field parses:

| You type | What happens |
|---|---|
| `tomorrow at 5pm` | Due tomorrow at 5 PM |
| `in 2 days` | Relative due date |
| `later`, `end of day`, `eod` | Due by 5 PM today |
| `@home` | Put it in the Home list (matched against your list names) |
| `high priority` | High priority — `medium`, `low`, and `p1`–`p3` work too |
| `at the office` | Add a location reminder (geofenced alarm) |
| `#groceries` | Tag it (colored chip) |
| `tomorrow` | All-day reminder for tomorrow — add a time to make it timed |

Notes:
- A date with no time is an all-day reminder.
- An unmatched `@list` stays in the title so nothing is silently lost.
- A bare clock time that already passed rolls over to tomorrow.

Press **Enter** to move from the title to the description, **Enter** again to
create. **Shift+Enter** inserts a new line.

## Search

The search field filters the list; all conditions combine:

| You type | Matches |
|---|---|
| `@work` | Only the Work list |
| `#urgent` | Titles or notes tagged with it |
| `!!` | High priority only |
| `text` | Any title or note containing it |

Click any `#tag` chip to filter the whole list to that tag (search still
combines with it); click the active chip again — or the ✕ next to the filter —
to clear. The filter persists across launches as the app's default view.

## Keyboard

Once the list is focused (Tab into it from the search field), the whole
popover runs from the keyboard:

| Keys | Action |
|---|---|
| `⌥⌘R` | Open remr from anywhere (global hotkey) |
| `↑` / `↓` | Move the selection |
| `Page Up` / `Page Down` | Move by a page |
| `Space` / `⇧Space` | Scroll |
| `Enter` | Complete a reminder (restore a deleted one, expand a tab) |
| `⌘Enter` | Open in Reminders |
| `⌫` | Delete (delete forever in Recently Deleted) |
| `←` | Open / close Recently Completed and Recently Deleted |
| `Tab` | Next field: title → notes → search → list (Shift+Tab goes back) |
| `⌘F` | Focus search |
| `Esc` | Step back: clear the selection, then the search, then close |

Every shortcut is rebindable. Click the gear icon in the popover — or press
**⌘,** — to open Settings, click a keycap to capture a new chord, then Save;
changes apply immediately and persist across launches, and **Reset to
defaults** restores the table above. The global hotkey must be exactly one
plain key plus any modifiers.

## Managing reminders

- Click the circle to complete it — it lands in **Recently Completed**.
- Right-click a row → Delete to delete it. EventKit has no trash, so remr keeps a local shadow copy: restore it from **Recently Deleted** while it's listed, or delete it forever there.
- Click a row to open the reminder in Reminders.
- Right-click the menu bar icon for **Refresh** and **Quit**.

## Requirements

- macOS 13 or later
- Xcode or Command Line Tools for building (no third-party dependencies)

## Install & build

```bash
git clone https://github.com/Loic-Lemon/remr.git
cd remr
swift build            # produces .build/debug/remr
Scripts/make-bundle.sh # produces build/Build/Products/Debug/remr.app
```

`make-bundle.sh` assembles and ad-hoc signs a proper `.app` bundle (the
Reminders entitlement is applied automatically). Copy `remr.app` to
`/Applications` — that's the way to run remr day-to-day. The bare binary
(`swift run remr`) is unsigned and lacks the Reminders entitlement, so it
can't access your reminders; use it only to smoke-test the build.

On first launch, grant Reminders access when prompted. If you denied it,
enable it under **System Settings → Privacy & Security → Reminders**.

## Development

- `swift test` runs the unit tests (requires full Xcode — XCTest is not in Command Line Tools).
- `Scripts/parser-check.sh` runs the parser harness with just Command Line Tools.
- Layout: `Sources/remr/Core/Parser/` holds the pure, unit-tested natural-language and search parsers; `Sources/remr/Core/ReminderStore.swift` is the EventKit layer plus the Recently Deleted shadow store (`~/Library/Application Support/remr/deleted.json`).
- The macOS Service is registered in `Support/Info.plist` (`NSServices` → *Create Reminders*).
