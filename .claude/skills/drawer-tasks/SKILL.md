---
name: drawer-tasks
description: Read and edit the markdown task file that the Drawer macOS menu bar app shows. Use when adding, checking off, scheduling, or noting tasks in a file whose day sections are dated `## YYYY-MM-DD` headings with `- [ ]` checkboxes, or when the user mentions Drawer, their day file, today's tasks, or a focus timer length.
---

Drawer reads one plain markdown file and shows today's tasks in a menu bar
panel. Checking a box in the panel writes back to this file, and editing the
file updates the panel. You edit the same file by hand.

## Find the file

There is no fixed path. Drawer points at a file the user chose (often a note
in an Obsidian vault). Ask which file, or look for a markdown file with
`## YYYY-MM-DD` headings and `- [ ]` tasks under them. Do not assume a path.

## Format

Tasks are checkboxes under a dated `## ` heading. The first `YYYY-MM-DD`
anywhere in the heading is the day, so `## 2026-06-08` and `## Mon 2026-06-08`
both work.

```
## 2026-06-08
- [ ] Call the landlord (15m)
- [x] Buy milk
- [/] Draft the report
```

- `[ ]` open, `[x]` done, `[/]` in progress (same glyph Obsidian uses).
- `(15m)` at the end sets the focus timer length in minutes, 1 to 480.
  Leave it off to get the 25 minute default.

Indented lines right under a task, until the next blank line or task, are that
task's note:

```
- [ ] Call the landlord
    Ask about the lease renewal.
    Mention the broken heater too.
```

## Sections

- Dated headings are days. Tasks on dates before today carry over until done.
  The nearest future date shows as tomorrow.
- `## Backlog` and `## Archive` (any case) are not days. Use them for undated
  tasks and finished ones. `### ` subheadings group tasks inside a section.

## Rules

- Add tasks under the right dated heading. Create the `## YYYY-MM-DD` heading
  if that day has none.
- To finish a task, change `[ ]` to `[x]`. Keep the rest of the line.
- Keep it plain and hand-writable. No tables, no HTML, no extra markup. That
  simplicity is the point: the file has to stay easy for a person to edit.
