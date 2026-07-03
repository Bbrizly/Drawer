# Drawer

[![Download latest release](https://img.shields.io/github/v/release/Bbrizly/Drawer?label=Download)](https://github.com/Bbrizly/Drawer/releases/latest)

A slide-out todo panel for macOS with a built-in focus timer. It lives at the
top-left edge of the screen and toggles with a global hotkey. The task list is
a plain markdown file, so you can edit it anywhere and the panel stays in sync.

## Download

Get the latest build from [Releases](https://github.com/Bbrizly/Drawer/releases/latest).

1. Download **Drawer-macOS.zip**.
2. Unzip it to get **Drawer.app**.
3. Drag **Drawer.app** into **Applications**.
4. The first time you open it, right-click the app and choose **Open**. macOS
   blocks unsigned apps until you do that once.

Requires macOS 26 or later.

## Why

I keep my day in one markdown file. I wanted to see it and check things off
without opening an app or switching windows. Drawer reads that file, shows
today's tasks, and writes checkboxes back to it.

## Features

- Global hotkey to show and hide (default Control-Option-Space)
- Today, Carried over, and Tomorrow sections, derived from dated headings
- Collapsible Backlog and Archive sections, with `###` subgroups
- Focus timer with pause, resume, and a completion sound
- Work mode that logs real hours against each task, with an end-of-day summary
- Focus sounds (white, pink, brown, green, ocean) and a pick of check-off sounds
- A notes pad with a teleprompter that floats over other apps
- Swipe a row to delete it or flag it in progress
- Task notes, written back as indented lines under the task
- Six themes, from calm system materials to art-directed worlds
- Turn any feature on or off, or strip the app down to Minimal
- Edits sync live from Obsidian, an editor, or iCloud
- Respects Reduce Motion

## Build from source

    make app && open Drawer.app

`make install` copies it to /Applications.

## File format

    ## 2026-06-08
    - [ ] Call the landlord
    - [x] Done task

A `##` heading with a date starts a day. Tasks under it belong to that day.
Weekday prefixes like `## Mon 2026-06-08` work. `## Backlog` and `## Archive`
collect non-day tasks and show collapsed at the bottom. Inside those, `###`
subheadings become group labels. A duration like `(15m)` sets the timer hint
for a task.

## Themes

Switch in Settings (Command-comma):

- Liquid Glass: macOS 26 glass plate (default)
- Reminders: opaque and high-contrast
- Widget: rounded type, minimal chrome
- Medieval: aged parchment with a gold-ruled frame
- Pixel: an 8-bit game window with a bitmap font
- Artistic: a vibrant mesh gradient

## Controls

- Hotkey: show and hide
- Esc: hide, after clicking into the panel
- Plus: add a task to today
- Note: open the notes pad and teleprompter
- Filter: hide completed, unchecked first
- Briefcase: start or end work mode, then tap a task to track time
- Speaker: play a focus sound
- Arrows: expand to full height or collapse
- Circle: check off a task, written back to the file
- Timer field and play: start a focus session
- Menu bar icon: toggle, settings, quit

## Requirements

macOS 26 or later. Swift 6.2.

## Test

    swift test
