# The Bureau: artist guide

Everything you see and hear in the Bureau is editable without touching
Swift. This page says where each knob lives and what it changes. When a
knob is not enough, the file map at the bottom says which source file
draws the thing so you know where to go.

## The one loop that matters

The Bureau reads its whole look and feel from one json file:

```
~/Library/Application Support/Drawer/bureau-tuning.json
```

Edit it in any text editor, save, and the app applies it live. No
rebuild, no restart. Slips re-render, the furniture recolors, physics
values land on paper already in the drawer. That is the workflow: keep
the drawer open on one side of the screen, the json on the other, and
nudge numbers until it feels right.

Two more ways to reach the same values:

- Settings > Bureau. Every number has a slider there. Sliders write the
  same json, so both stay in sync.
- Long-press the tray button in the drawer header. Same sliders in a
  floating panel, for tuning while you rummage.

Colors and the font name are json-only (plus the font field in the
panel). Everything numeric has a slider.

To reset everything: quit the app, delete bureau-tuning.json, reopen.
The defaults regenerate.

## The art block

The `art` section of the json is the whole visual identity:

```json
"art": {
  "paper":       "#E3D6B8",
  "paperShade":  "#CCBD9C",
  "ink":         "#292621",
  "inkFaint":    "#2926218C",
  "accent":      "#9E3326",
  "approve":     "#3D6B38",
  "drawerFloor": "#3D3624",
  "drawerLip":   "#292417",
  "tray":        "#5E523D",
  "trayInk":     "#DED4BA",
  "metal":       "#262626",
  "metalEdge":   "#525252",
  "rivet":       "#6B6B6B",
  "fontFamily":  "Pixelify Sans",
  "titleFontSize": 15,
  "detailFontSize": 8,
  "pixelScale": 2
}
```

What each color paints:

| Key | Paints |
|---|---|
| `paper` | The receipt slips and sticky notes |
| `paperShade` | The shaded band at a slip's foot, and the yellowing of old paper |
| `ink` | Task titles on slips and stickies |
| `inkFaint` | Detail lines, the stub line, subtask text |
| `accent` | The red rule under a title, the DENIED stamp, delete accents |
| `approve` | The APPROVED stamp green |
| `drawerFloor` | The drawer floor behind the slips |
| `drawerLip` | The dark lip at the drawer's front edge and the dark slots |
| `tray` | The FILED tray band along the bottom |
| `trayInk` | Light text on dark surfaces (the FILED label, shredder teeth) |
| `metal` | The stamp rack's slab and its right-edge tab |
| `metalEdge` | The lighter stroke around the rack |
| `rivet` | The four rivet dots on the rack corners |

Colors are `#RRGGBB` or `#RRGGBBAA` hex. A string that does not parse
renders magenta, so a typo is visible instead of silently black.

One honest caveat: slips and the drawer furniture recolor live on save.
Floating stickies and an open stamp rack pick the new colors up when
they are next opened (drag the slip out again, or close and reopen the
rack). That is a known simplification, not a bug you caused.

## Pixelation

`pixelScale` is the chunkiness dial. The slips render into a smaller
pixel buffer and scale back up with nearest-neighbor, so edges stay
hard and blocky instead of smoothing out.

- `1` is crisp Retina. No chunk.
- `2` (the default) renders at half density. Reads as game pixels.
- `3` to `4` gets very chunky. Titles stop being readable past 3 at
  the default slip size.

The printer preview, the drawer slips, and the filed tray all follow
it. Stickies are drawn as live vector UI, so they take the pixel font
but not the buffer chunk.

## Fonts

`fontFamily` names the face for every Bureau text surface: slip titles,
details, the FILED label, stamp plates, sticky text.

The app ships Pixelify Sans (OFL licensed) and uses it by default. To
try a different face:

1. Get a `.ttf`. For the Papers, Please flavor look at Silkscreen,
   VT323, Press Start 2P, or Departure Mono. All are free on Google
   Fonts under the OFL.
2. Drop the file into `Sources/Drawer/Resources/Fonts/`.
3. Rebuild and reinstall (`make app && make install`). The app
   registers every ttf in that folder at launch.
4. Set `fontFamily` in the json to the font's family name (the name
   Font Book shows, not the file name).

Any font already installed on your Mac works with step 4 alone, no
rebuild. Bundling is only needed if you want the app self-contained.

`titleFontSize` and `detailFontSize` size the slip text in points.
Titles wrap; if a long title clips, drop the size or raise the slip
height (`sticky.slipWidth` / `sticky.slipHeight` size the paper
itself).

## The stamp rack

The `stamp` block. Geometry first:

| Key | What |
|---|---|
| `stampSizePx` | The head's square footprint. Default 96, big and pressable |
| `rackWidthPx` | The pulled-out slab holding the two heads |
| `rackHeightPx` | The slab's height |
| `tabWidthPx` | The collapsed tab at the right screen edge |

Then the press feel: `extendMs` (rack slide), `pressMs` (head down),
`liftMs` (head up), `inkRotationMinDeg`/`inkRotationMaxDeg` (how
crooked the ink lands), `doubleStrikeOffsetPx` (the ghost of a double
strike), `thunkVolume`, `slideVolume`, `hapticEnabled`.

The ink lands slightly rotated and double-struck on purpose. That
haphazardness is the Papers, Please read; set both rotation values to
0 for clean ink.

## The printer (how receipts spawn)

The `print` block. A queued task prints line by line from the seam,
tears off, and drops into the drawer:

- `stepMs` and `stepPx`: the thermal-printer reveal. Smaller stepPx and
  bigger stepMs is slower and grindier.
- `tearMs`: the pause before the slip tears off.
- `dropImpulse`: how hard the torn slip is pushed into the drawer.
  Default 3 lays it down gently. Raise it toward 20 for chaos.
- `spreadDeg`: the half-angle of the push direction. 0 is straight
  down, 90 is anywhere sideways.
- `spin`: how much the slip rotates as it falls.
- `impulseVariance`: randomness on the push, 0 to 1.
- `queueStaggerMs`: the gap between queued receipts.
- `chatterVolume` and `dingVolume`: the print tick and the end bell.

## The shredder

Off by default. `shredder.enabled` turns it back on: the toothed slot
in the tray's right corner plus the screen-corner overlay for floating
stickies. When it is off nothing in the Bureau can delete a receipt;
paper leaves only by being stamped.

Shredding deletes only the Bureau's receipt. The task line in
Drawer.md is never touched.

Size and feel: `widthPx` (the tray slot), `overlayWidthPx` and
`overlayHeightPx` (the screen overlay), `shredMs`, `volume`.

## Paper feel, in one paragraph each

`physics` is the rummage: `repulsionRadius` and `repulsionStrength`
are how far and how hard the cursor shoves paper, `friction`,
`restitution`, and the damping pair are how the paper skids and
settles, `papersCollide` lets slips push each other, `rotationEnabled`
and `maxTiltDeg` bound the spin. Gravity is 0 because the drawer is
top-down; give it a negative value and paper falls to the bottom edge.

`texture.showStubLine` is the "NO. 1234 BUREAU FILING" footer line.
Off by default; turn it on if you want the transaction-stub flavor
back. `texture.vignetteAlpha` is the dark edge shadow over the whole
scene, 0 to disable.

`drawer` shapes the furniture: tray height, lip height, how filed
slips stack (`traySlotSpacing`, `trayScale`, `trayVisibleCap`), and
the tilt of freshly spawned paper. `sticky` sizes the paper itself
(`slipWidth`, `slipHeight`) and the pull-out scale when you drag a
slip out of the drawer. `hoverScroll` is the two-finger note move.
`rustle` is the paper sound as it slides. `transition.pushMs` and its
bezier are the drawer push animation (the bezier stays a hand edit).

## When the json is not enough: the file map

All Bureau source lives in `Sources/DrawerBureau/`. Each visual has
one home:

| You want to change | Go to |
|---|---|
| How a slip is drawn (tears, rule, layout, aging) | `TextureRenderer.swift`, the `draw` method |
| The palette plumbing and hex parsing | `TextureRenderer.swift`, `BureauPalette` |
| The stamp heads and rack drawing | `StampRack.swift` (`StampHeadView`, `StampRackView`) |
| The drawer furniture (tray, lip, vignette, shredder slot) | `BureauScene.swift`, `layoutDrawerFurniture` |
| The floating sticky layout | `StickyView.swift` |
| The shredder overlay panel | `ShredderOverlay.swift` |
| The printer reveal | `PrinterSlot.swift` |
| Every sound (all synthesized, no asset files) | `BureauSounds.swift`, the `render` recipes |
| The tuning schema and defaults | `BureauTuning.swift` |
| The slider panel | `BureauTuningPanel.swift` |

Two notes for bigger art swaps:

Slips are procedural. If you would rather paint one, the clean seam is
`TextureRenderer.draw`: replace its drawing with an `NSImage` you load,
draw the title text over it, and everything downstream (printing,
physics, aging, filing) keeps working, because they only ever see the
finished image.

Sounds are synthesized PCM, each one a small recipe in
`BureauSounds.render`. To use a recorded sample instead, load a wav
into an `AVAudioPCMBuffer` in `init` and skip the recipe. Keep them
under half a second; the drawer plays them fast and often.

## Rules of thumb

Change one number at a time and save; the reload is instant, so tight
loops beat big rewrites. If paper stops moving the way you expect,
compare against a fresh default file before hunting deeper. And if a
color comes out magenta, the hex string has a typo.
