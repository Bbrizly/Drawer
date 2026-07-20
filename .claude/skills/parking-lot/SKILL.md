---
name: parking-lot
description: Read and edit the markdown idea file behind the Drawer app's parking lot, where each idea renders as a car in a painted stall. Use when adding, sorting, recolouring, or cleaning up ideas in a `Parking lot.md` file whose sections are `## ` bay headings with `- ` idea lines, or when the user mentions the parking lot, parked ideas, or sorting their ideas into bays.
---

Drawer renders one plain markdown file as a parking lot: each `## ` heading is
a bay of painted stalls, each `- ` line is a car. The app watches the file, so
an edit here shows up in the lot right away. You edit the same file by hand.

## Find the file

`Parking lot.md`, in the same folder as the drawer task file (often an
Obsidian vault). There is no other location. If you cannot find it, ask.

## Format

```
## Unsorted
- Wild thought (2026-07-19)

## Apps
- Lock screen widget (2026-07-19 yellow)
    A tiny glanceable version. Maybe just the next task,
    nothing else.
- Pluck for Instagram (2026-03-02 pink)

## Hardware
- Build a macropad (2026-05-11 blue)
```

- `## Name` starts a bay. Bays render in file order, so order matters.
- `- Title` is one idea, one car. Ideas render in file order within the bay.
- The trailing paren is metadata. Both parts optional, either order,
  space separated: a date `YYYY-MM-DD` (when it was parked) and a colour.
- Colours are exactly `yellow pink blue green purple gray`. Nothing else.
  No colour means yellow.
- Lines indented under an idea, until the next blank line, are its details.
  The app writes details indented four spaces; match that.
- A paren that holds anything else (`(maybe)`, `(15m)`) is just title text.
  Leave it alone.

## Rules

- Preserve what you do not understand. Prose, comments, or odd lines between
  ideas belong to the user. Move and edit idea lines, never rewrite the file
  wholesale.
- New captures go to the `## Unsorted` bay at the top, stamped with today's
  date. Create that bay at the top of the file if it is missing.
- When moving an idea between bays, carry its date, colour, and detail lines
  with it unchanged.
- Keep one blank line between bays.
- Do not add positions, ids, or any metadata beyond the date and colour.
  A car's place in the lot is its place in the file; that is the whole design.

## Common jobs

- **Add an idea**: append `- Title (YYYY-MM-DD)` to the right bay, or to
  Unsorted if unsure. Details indented four spaces underneath.
- **Sort the lot**: move idea lines (with their details) out of Unsorted into
  bays that make sense. Create new `## ` bays freely. Delete a bay heading
  only when it is empty and clearly dead.
- **Recolour**: edit the colour token in the paren, keeping the date. Colour
  is a good grouping tool (for example green for quick wins).
- **Prune**: delete the idea line and its details. No tombstone needed.
