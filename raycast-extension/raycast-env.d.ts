/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {}

/** Preferences accessible in all the extension's commands */
declare type Preferences = ExtensionPreferences

declare namespace Preferences {
  /** Preferences accessible in the `calendar` command */
  export type Calendar = ExtensionPreferences & {}
  /** Preferences accessible in the `add-reminder` command */
  export type AddReminder = ExtensionPreferences & {}
}

declare namespace Arguments {
  /** Arguments passed to the `calendar` command */
  export type Calendar = {}
  /** Arguments passed to the `add-reminder` command */
  export type AddReminder = {
  /** send invoice tomorrow @work */
  "text": string
}
}

