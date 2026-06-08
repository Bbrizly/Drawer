# Drawer

A slide-out todo panel for macOS with a built-in focus timer. It lives at the
top-left edge of the screen and toggles with a global hotkey. The task list is
a plain markdown file, so you can edit it anywhere and the panel stays in sync.

## Why

I keep my day in one markdown file. I wanted to see it and check things off
without opening an app or switching windows. Drawer reads that file, shows
today's tasks, and writes checkboxes back to it.

## Features

- Global hotkey to show and hide (default Control-Option-Space)
- Today, Carried over, and Tomorrow sections, derived from dated headings
- Collapsible Backlog and Archive sections, with `###` subgroups
- Focus timer with pause, resume, and a completion sound
- Three themes: Liquid Glass, Reminders, Widget
- Edits sync live from Obsidian, an editor, or iCloud
- Respects Reduce Motion

## Build

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

## Controls

- Hotkey: show and hide
- Esc: hide, after clicking into the panel
- Plus: add a task to today
- Filter: hide completed, unchecked first
- Arrows: expand to full height or collapse
- Circle: check off a task, written back to the file
- Timer field and play: start a focus session
- Menu bar icon: toggle, settings, quit

## Requirements

macOS 26 or later. Swift 6.2.

## Test

    swift test
