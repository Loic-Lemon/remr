import { Action, ActionPanel, Icon, LaunchProps, List, closeMainWindow, open, showHUD, showToast, Toast } from "@raycast/api";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { randomUUID } from "node:crypto";
import { readFile, unlink } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { useRef, useState } from "react";

function reminderURL(action: "add" | "compose", text: string, requestId?: string): string {
  // URLComponents treats + literally, so use percent-encoded spaces.
  const query = `text=${encodeURIComponent(text)}`;
  return `remr://${action}?${query}${requestId ? `&requestId=${requestId}` : ""}`;
}

async function waitForResult(requestId: string): Promise<{ success: boolean; message: string }> {
  const path = join(homedir(), "Library/Caches/remr/raycast-results", `${requestId}.json`);
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    try {
      const result = JSON.parse(await readFile(path, "utf8"));
      await unlink(path).catch(() => undefined);
      if (typeof result.success !== "boolean" || typeof result.message !== "string") {
        throw new Error("Invalid confirmation from remr.");
      }
      return result;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    }
    await new Promise((resolve) => setTimeout(resolve, 150));
  }
  throw new Error("No confirmation yet. Check Reminders before retrying to avoid a duplicate.");
}

export default function AddReminder(props: LaunchProps<{ arguments: { text?: string } }>) {
  const [text, setText] = useState(props.arguments.text ?? "");
  const [saving, setSaving] = useState(false);
  const inFlight = useRef(false);
  const trimmed = text.trim();

  async function create() {
    if (!trimmed || inFlight.current) return;
    inFlight.current = true;
    setSaving(true);
    const toast = await showToast({ style: Toast.Style.Animated, title: "Creating reminder…" });
    try {
      const requestId = randomUUID();
      await promisify(execFile)("/usr/bin/open", ["-g", reminderURL("add", trimmed, requestId)]);
      const result = await waitForResult(requestId);
      toast.style = result.success ? Toast.Style.Success : Toast.Style.Failure;
      toast.title = result.success ? "Reminder Created" : "Couldn't Create Reminder";
      toast.message = result.message;
      if (result.success) await showHUD(`Created: ${result.message}`, { clearRootSearch: true });
    } catch (error) {
      toast.style = Toast.Style.Failure;
      toast.title = "Couldn't Confirm Reminder";
      toast.message = error instanceof Error ? error.message : String(error);
    } finally {
      inFlight.current = false;
      setSaving(false);
    }
  }

  return (
    <List
      searchText={text}
      onSearchTextChange={setText}
      searchBarPlaceholder="send invoice tomorrow @work"
      filtering={false}
      isLoading={saving}
    >
      {trimmed ? (
        <List.Item
          icon={Icon.PlusCircle}
          title={trimmed}
          subtitle={saving ? "Creating…" : "Create reminder"}
          actions={
            <ActionPanel>
              <Action title="Create Reminder" icon={Icon.PlusCircle} onAction={create} />
              <Action
                title="Review in Remr"
                icon={Icon.Pencil}
                shortcut={{ modifiers: ["cmd"], key: "return" }}
                onAction={async () => {
                  if (inFlight.current) return;
                  await closeMainWindow();
                  await open(reminderURL("compose", trimmed));
                }}
              />
            </ActionPanel>
          }
        />
      ) : (
        <List.EmptyView icon={Icon.PlusCircle} title="What do you need to do?" description="Type a reminder. Return creates it; ⌘Return opens it in remr for review." />
      )}
    </List>
  );
}
