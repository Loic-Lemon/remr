import { open } from "@raycast/api";

export default async function CalendarCommand() {
  await open("remr://calendar");
}
