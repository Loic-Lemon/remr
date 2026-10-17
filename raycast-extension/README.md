# Remr for Raycast

Two commands for the installed remr app:

- **Agenda** opens remr's calendar.
- **Add Reminder** accepts natural language such as `send invoice tomorrow @work`.
  Type in the command's search field and press **Return** to create it, or
  **⌘Return** to open remr's prefilled composer for review. You can also supply
  the text as a Raycast command argument. Dates, lists, tags, and priorities use
  remr's existing parser; no local model is needed.

Creation is confirmed only after remr saves to Reminders. Permission, parsing,
unknown-list, location, and save errors appear in Raycast without clearing your
input. If confirmation times out, check Reminders before retrying.

## Develop locally

1. Install remr from the repo root with `./install.sh`.
2. From this directory, run `npm install` then `npm run dev`.
3. Search Raycast for **Add Reminder** or **Agenda**. Assign a hotkey or alias in
   Raycast settings for faster access.

This is a local extension project and is not yet published to the Raycast Store.

## App integration

`remr://calendar` opens the calendar; `remr://compose?text=…` opens Quick Add with
prefilled text; `remr://add?text=…&requestId=<UUID>` creates directly. Query values
must be URL-encoded. For direct creation, remr writes a JSON confirmation to
`~/Library/Caches/remr/raycast-results/<lowercase-UUID>.json`; the extension reads
and removes it. The confirmation contains `success` and `message`. No reminder
content is sent over the network.
