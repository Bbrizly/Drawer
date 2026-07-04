<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Docs/media/readmeLogo-dark.png">
    <img src="Docs/media/readmeLogo.png" width="200" alt="Drawer icon">
  </picture>
</p>

<h1 align="center">Drawer</h1>

<p align="center">
  <em>Your day is a text file. Drawer just slides it into view.</em>
</p>

<p align="center">
  <a href="https://github.com/Bbrizly/Drawer/releases/latest"><img src="https://img.shields.io/github/v/release/Bbrizly/Drawer?style=flat-square&color=111111&label=download" alt="Download latest release"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-111111?style=flat-square" alt="macOS 26 or later">
  <img src="https://img.shields.io/badge/Swift-6.2-111111?style=flat-square" alt="Swift 6.2">
  <img src="https://img.shields.io/badge/themes-8-111111?style=flat-square" alt="Eight themes">
</p>

<p align="center">
  <img src="Docs/media/themes.gif" width="380" alt="Drawer shown in eight themes">
</p>

Drawer is a menu bar app for macOS. It lives at the top-left edge of the
screen and slides out with a global hotkey. Inside is today's to-do list, read
straight from a plain markdown file, plus a focus timer to work through it.

The list is just text, so you can edit it in Obsidian, an editor, or iCloud,
and the panel stays in sync. Check a task off in the panel and the checkbox is
written back to the file. Nothing to sync, no account, no database. Your tasks
stay yours.

## Why

I keep my whole day in one markdown file. I wanted to see it and check things
off without opening an app or switching windows. Drawer reads that file, shows
today's tasks, and writes the checkboxes back. That is the whole idea. Every
other feature is optional and can be switched off.

## Features

- Global hotkey to show and hide, default Control-Option-Space
- Today, Carried over, and Tomorrow sections, built from dated headings
- Collapsible Backlog and Archive sections, with `###` subgroups
- Focus timer with pause, resume, and a completion chime
- Pomodoro mode that runs a focus, short break, long break cycle
- A stopwatch that logs real hours against each task, with an end-of-day summary
- An idea board you jot to and swipe over to, kept in the same file
- Focus sounds, white, pink, brown, green, ocean, and a pick of check-off sounds
- A notes pad with a teleprompter that floats over other apps
- Swipe a row to delete it or flag it in progress
- Task notes, written back as indented lines under the task
- Eight themes, from calm system materials to art-directed worlds
- Turn any feature on or off, or strip the app down to Minimal
- Edits sync live from Obsidian, an editor, or iCloud
- Respects Reduce Motion

## Themes

Switch in Settings, Command-comma.

- **Liquid Glass**: macOS 26 glass plate, the default
- **Reminders**: opaque and high-contrast
- **Widget**: rounded type, minimal chrome
- **Medieval**: aged parchment with a gold-ruled frame
- **Pixel**: an 8-bit game window with a bitmap font
- **Artistic**: a vibrant mesh gradient
- **Notebook**: ruled paper with a handwritten feel
- **Windows XP**: the Luna desktop, blue title bar and beige toolbar

## File format

Tasks are markdown checkboxes under a dated heading.

    ## 2026-07-04
    - [ ] Call the landlord (15m)
    - [x] Done task

A `##` heading with a date starts a day, and the tasks under it belong to that
day. Weekday prefixes like `## Mon 2026-07-04` work too. `## Backlog` and
`## Archive` collect tasks with no date and show collapsed at the bottom.
Inside those, `###` subheadings become group labels. A duration like `(15m)`
sets the focus timer hint for a task.

Indent lines right under a task to give it a description. Everything indented
until the next blank line is the note.

    - [ ] Call the landlord
        Ask about the lease renewal.
        Mention the broken heater too.

It is meant to be easy to write by hand or by an AI. That is the whole format.

## Download and install

Get the latest build from
[Releases](https://github.com/Bbrizly/Drawer/releases/latest).

1. Download **Drawer-macOS.zip**.
2. Unzip it to get **Drawer.app**.
3. Drag **Drawer.app** into **Applications**.
4. The first time, right-click the app and choose **Open**. macOS blocks
   unsigned apps until you do that once.

## Controls

- **Hotkey**: show and hide
- **Esc**: hide, after clicking into the panel
- **Plus**: add a task to today
- **Note**: open the notes pad and teleprompter
- **Light bulb**: jot an idea, or swipe to the idea board
- **Filter**: hide completed, unchecked first
- **Briefcase**: start or end the stopwatch, then tap a task to track time
- **Speaker**: play a focus sound
- **Arrows**: expand to full height or collapse
- **Circle**: check off a task, written back to the file
- **Timer field and play**: start a focus session
- **Menu bar icon**: toggle, settings, quit

## Build from source

    make app && open Drawer.app

`make install` copies it to /Applications.

## Requirements

macOS 26 or later. Swift 6.2.

## Test

    swift test
