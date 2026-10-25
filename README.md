# chopstix 🥢

A cute, simple sticky-note app for macOS. Each note is a bowl of noodles held up on your
screen by a pair of chopsticks; all of them live on a menu-style board.

<p align="center">
  <img src="docs/screenshots/note-prawnMee.png" width="200" alt="Prawn Mee note">
  <img src="docs/screenshots/note-ramen.png" width="200" alt="Ramen note">
  <img src="docs/screenshots/note-matchaSoba.png" width="200" alt="Matcha Soba note">
  <img src="docs/screenshots/note-laksa.png" width="200" alt="Laksa note">
  <br>
  <img src="docs/screenshots/note-pho.png" width="200" alt="Pho note">
  <img src="docs/screenshots/note-japchae.png" width="200" alt="Japchae note">
  <img src="docs/screenshots/note-udon.png" width="200" alt="Udon note">
</p>

| The menu board | Editing a note in the board |
| :---: | :---: |
| <img src="docs/screenshots/board.png" width="420" alt="Menu board"> | <img src="docs/screenshots/editor-sheet.png" width="360" alt="Note editor sheet"> |

Screenshots are rendered straight from the SwiftUI views with
`swift run Chopstix --snapshot <dir>` (sample notes, your real notes are untouched).

## Build & run

Requires macOS 14+ and the Swift 6 toolchain (Xcode or just the Command Line Tools).

```sh
scripts/build_app.sh            # → build/Chopstix.app
open build/Chopstix.app
scripts/build_app.sh --install  # copy to /Applications

swift run Chopstix              # quick dev run, no bundle
scripts/test.sh                 # unit tests
swift run Chopstix --snapshot /tmp/chopstix-snaps   # render the design to PNGs
```

Notes are stored in `~/Library/Application Support/Chopstix/notes.json`
(override with `CHOPSTIX_DATA_DIR=/some/dir`).

## Using it

| | |
| --- | --- |
| New sticky note | ⌘N, the menu-bar chopsticks, or **order a note** on the board |
| New note that stays in the board | ⇧⌘N |
| Show the board | ⌘0, or click the Dock icon |
| Move a note | drag the chopsticks / top edge |
| Resize a note | drag the folded bottom-right corner |
| Put a note back in the board | ⌘W, or ⋯ → Return to Menu Board |
| Bold / italic / underline / strikethrough | ⌘B / ⌘I / ⌘U / ⇧⌘X |
| Bulleted list / checklist | ⇧⌘7 / ⇧⌘L — Return continues the list, Return on an empty item ends it |
| Tick a box | click it |
| Flavour, always on top, delete | hover a note → ⋯ |

Flavours: Prawn Mee, Ramen, Matcha Soba, Laksa, Pho, Japchae, Udon.
