# README demo runbook

Goal: a 30–45 second silent recording of capture → plan → finish in the actual
remr UI. Preparation does not start a recording or replace the existing README video.

## Isolated app

```bash
Scripts/demo.sh prepare   # Build build/Demo/remr Demo.app; does not launch it
Scripts/demo.sh start     # Quit normal remr and launch a fresh demo
Scripts/demo.sh reset     # Relaunch demo with the original fictional data/settings
Scripts/demo.sh stop      # Quit demo and return to /Applications/remr.app
```

The demo bundle has its own identity (`com.local.remr.demo`) and executable
(`remr-demo`). It always selects demo mode from that identity; no preference can
turn it into a live reminder session. It does not register the `remr://` URL scheme
or the Create Reminders service. Hover over its menu bar icon to confirm
“remr Demo — fictional reminders”. Do not launch both apps together: their global
shortcuts would compete. Use the script rather than opening the production app.

All demo reminders, completions, edits, rescheduling and deleted-item recovery
stay in memory. No EventKit permission request, fetch, save or delete is performed;
“View in Reminders” does nothing. The EventKit objects used to render the real UI
are unsaved objects. Personal deleted-reminder history is neither loaded nor saved.
Settings, filters, tag colors, voice history and usage metrics use a separate demo
preferences domain, reset on every demo launch. Normal remr keeps its existing data
and settings. Demo mode is also available with `--demo` for development checks.

The initial scene contains seven active tasks and one completed task across Work,
Personal and Errands. Dates are relative to launch day, with timed and all-day
examples. The notch is enabled, review nudges are disabled and local AI is off.
No real reminder sync is demonstrated: the recording should be described as using
sample data. Microphone, location and local AI are outside this recording's scope.

## Before the take

1. Run `Scripts/demo.sh start`. Confirm the demo tooltip and fictional list names.
2. Enable Focus/Do Not Disturb, hide personal windows, and use a clean wallpaper.
   These desktop changes are manual; the preparation script does not alter them.
3. Open with `⌥Space`; check that the notch and calendar fit the chosen capture area.
4. Choose a capture area that includes the top edge and the calendar's full expanded
   size, with readable text. Avoid cropping only to the small reminder panel.
5. Use macOS Screenshot (`⇧⌘5`) → Record Selected Portion, microphone off. Select
   the region, but start recording only when ready. macOS may require screen
   recording permission for other recording tools.
6. Close the panel and leave a short still frame before the first action.

## Storyboard

- **0–4 seconds:** clean desktop → `⌥Space` opens remr. Caption: “One shortcut away”.
- **4–15 seconds:** open the add composer and type
  `Send proposal tomorrow at 10am @work`. Pause for two seconds on the parsed
  date/list chips, then save. Caption: “Type it naturally”.
- **15–21 seconds:** show the new reminder in the list. Caption: “Ready to plan”.
- **21–32 seconds:** switch to the calendar (`C`), use week view if it reads more
  clearly, and drag the new reminder to the following day. Pause on the result.
  Caption: “Move plans as they change”.
- **32–40 seconds:** return to reminders (`C`), select the proposal and press Return
  to complete it. Pause, then Esc to close. Caption: “Done. Back to your day”.
- Leave two seconds of stillness at the end for trimming.

Use the composer’s visible save control if Return is being used for text editing.
If the new reminder is out of view, search for “Send proposal”; clear the search
before switching to the calendar. Reset between takes instead of manually undoing
all actions. A calendar month boundary may make week view the clearer framing.

## Recording and README handoff (later)

Trim dead time and keep the final video around 30–45 seconds. Export a readable
MP4 and a poster frame. Review the entire clip for private desktop content,
legibility, cursor pacing and correct fictional data. Keep screen and system audio
off unless deliberately needed; add short captions in editing.

Use the existing video position near the README introduction. The preferred
handoff is a GitHub video attachment plus a local poster image with useful alt
text and an explicit “sample data” caption. Decide the final upload destination
when recording; no placeholder video link is added now. Keep raw takes outside
git. Only add the selected compressed asset/poster when the recording is approved.

## Automation prerequisite

The current agent session reports “Computer Use permissions are not granted”.
Enable Computer Use for this session before asking the agent to drive the native
app for a rehearsal or recording. Functional checks and bundle launch verification
can run without that permission. Manual recording with macOS Screenshot is also
possible. No desktop recording or permission change is performed during preparation.

## Validation

```bash
Scripts/demo-check.sh
```

The standalone harness checks the seed scene, natural-language capture, list
resolution, rescheduling, completion, editing, tags, moving lists, snooze,
duplication, deletion/recovery and reset. It also checks that personal preferences
and the deleted-reminder file are unchanged. It runs with `--demo` and does not
request Reminders access. Rebuild the demo with `prepare` after changing source.

## Current README recording

The README links to `assets/new_demo.mp4` (about 20 seconds) through
`assets/demo-poster.jpg`, a frame from the recording showing the fictional
reminder list. The video is kept in the repository; a GitHub attachment upload
is optional if an inline player is desired later.
