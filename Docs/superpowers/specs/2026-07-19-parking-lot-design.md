# Spec 05: parking lot

The parking lot is one pinned board that holds every loose idea, laid out as
cars in painted stalls seen from above. Sections of the lot come from headings
in a markdown file, so the whole thing stays hand-writable and an AI can
re-sort it without touching a single coordinate.

Positioning line: park an idea, see the whole lot, drive one out when you want
to think about it.

## Agreed shape

- **One file, markdown, hand-writable.** `Parking lot.md` next to `Drawer.md`,
  resolved through the same chain and watched the same way. Not stored in
  `board.json`.
- **No stored positions.** A car's place in the lot is derived entirely from
  where its line sits in the file. There is no x/y to save, drag, or migrate.
- **Pinned first, never deletable.** The lot is the top row of the board
  selector. It cannot be renamed or removed.
- **Fixed rendering at every zoom.** Zoom magnifies, nothing else. No level of
  detail swap, no size or finish changes.
- **Cars are horizontal, always.** A car exits along its own long axis, which
  is what makes the whole layout work.
- Behind `feature.parkingLot`.

Deliberately out of v1: no images, no dragging a car between bays (change the
bay in the panel or edit the file), no age or staleness visuals.

## File format

```markdown
## Apps
- Lock screen widget (2026-07-19 yellow)
    A tiny glanceable version. Maybe just the next task,
    nothing else. Would need a share extension.
- Pluck for Instagram (2026-03-02 pink)

## Hardware
- Build a macropad (2026-05-11 blue)
```

`##` is a bay. `- ` is one idea, one car. Indented lines under an idea are its
details, the same rule the task file already uses: everything indented until
the next blank line belongs to that idea.

The trailing paren is metadata, the same shape as the task file's `(15m)`.
Both parts optional, either order, space separated:

- A date, `YYYY-MM-DD`. When you parked it. Written automatically on capture.
- A colour, one of `yellow pink blue green purple gray`, the exact keys
  `BoardItem.color` already uses. No second colour vocabulary.

Anything the parser does not recognise is left alone and written back
untouched. The file is yours first.

## Model and parsing (DrawerCore)

`ParkingLotParser` mirrors `TodoParser`. It produces:

```swift
public struct ParkedIdea {
    public var title: String
    public var details: String
    public var parked: Date?
    public var color: String?
    public var lineRange: Range<Int>   // for surgical writeback
}

public struct ParkingBay { public var name: String; public var ideas: [ParkedIdea] }
public struct ParkingLotDocument { public var bays: [ParkingBay] }
```

`ParkingLotStore` mirrors `NotesStore`: load on start, watch the file with
`FileWatcher`, debounced saves, no save button.

Writeback splices only the edited idea's `lineRange`. It never re-serialises
the whole document, so hand-written prose elsewhere in the file survives an
edit. This is the same instinct `TodoWriteback` follows for the task file.

## Layout

Bays render in file order. A bay is a block of stalls: cars stack vertically,
one per stall, in file order. When a block reaches the bottom of the view the
bay continues in the next block to the right.

Blocks sit side by side with bare asphalt between them. **There is no road.**
No lane markings, no centre line, no different surface. The gap is simply where
the painted stalls are not, which is how a real lot reads. Cars in every second
block are mirrored so each block noses into the gap on its own side.

This does not use `BoardCanvas`. Canvas exists to manage arbitrary positions,
images, and dragging, none of which apply here. A `ScrollView` with a
magnification gesture gives pan and zoom for a fraction of the code.

`CarSprite` is a small SwiftUI shape view in the old top-down GTA style: flat
body, hard dark outline, raked glass front and back, four wheels poking out at
the corners, headlights at the nose and red tails at the tail. Colour is
injected. **The car carries no text.** The idea's title is stencilled on the
asphalt in the stall below it, so a title can run as long as it likes and the
sprite stays clean.

## Pressing a car

The car noses straight out of its stall into the open space beside it, staying
horizontal. The space widens to make room, and the panel opens directly under
the car standing in it. Nothing inside the lot reflows; the stall blocks are
pushed outward.

The vacated stall keeps its stencil, so you can still see whose space is empty.

Press the car again, or press Escape, and it reverses back in.

## Editing

The panel is the markdown, not a form.

- The caret is placed on open. There is no edit mode and no pencil button.
- The first line is the title, the same rule the capture bar uses. Change it
  and the stencil on the asphalt changes with it.
- No save button. Debounced writeback, same as `NotesStore`.
- The bay name is a dropdown on the panel's meta line, listing the `##`
  headings already parsed. This is the only in-app way to move an idea between
  bays.
- Clearing all the text and closing the panel removes the idea. No delete
  button, no confirmation.

## Capture

`Park ◂` in the capture bar stops writing to `board.json` and appends to an
`## Unsorted` bay at the top of the lot file, stamped with today's date. The
button finally means what it says.

## AI sorting

No code. The lot is a markdown file, so "read all my ideas and sort them into
bays" is an agent editing text, which this setup already does well for the task
file. This is the entire reason the lot is markdown-backed rather than another
board in `board.json`.

## Tests

- Parser round-trip: parse then serialise leaves an unchanged file byte-identical.
- Metadata parsing: date only, colour only, both, neither, unknown junk.
- Details capture: indented lines attach to the right idea and stop at a blank line.
- Writeback splice: editing one idea leaves unrecognised surrounding lines intact.
- Layout: a bay overflows into the next block at the right point, bays keep
  file order.
