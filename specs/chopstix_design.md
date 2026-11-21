# chopstix — MVP plan & design

Companion to [chopstix_mvp.md](chopstix_mvp.md).

## Tech choices

| Concern | Choice | Why |
| --- | --- | --- |
| Language / UI | Swift 6 toolchain (Swift 5 language mode), SwiftUI views hosted in AppKit windows | SwiftUI for drawing the themed UI; AppKit for borderless floating note windows and a real text editor |
| Build | Swift Package Manager + `scripts/build_app.sh` to wrap the binary in `Chopstix.app` | Builds with Command Line Tools only — no Xcode project needed |
| App lifecycle | Plain `NSApplication` + `AppDelegate` (no SwiftUI `App` scenes) | Full control over note windows, the board window, menus and the menu-bar item |
| Editor | `NSTextView` subclass (TextKit 1) rendering markdown live | Undo, selection for free; see [markdown_design.md](markdown_design.md) |
| Persistence | JSON at `~/Library/Application Support/Chopstix/notes.json` | Human readable, trivially versionable |
| Min OS | macOS 14 | `@Observable`, modern SwiftUI |

## Data model

```
Note
  id: UUID
  number: Int            // "No. 07" on the menu board
  flavor: Flavor         // noodle design
  markdown: String       // body, stored as its own markdown/<id>.md file
  isOnScreen: Bool       // stuck around the screen vs. lives only in the board
  alwaysOnTop: Bool
  frame: CGRect?         // last on-screen window frame
  createdAt / updatedAt
```

Notes are plain markdown (see [markdown_design.md](markdown_design.md)). The MVP's
rich-text runs (`content: [TextRun]`) are only read now, to convert notes saved by older
versions.

## Architecture

```
main.swift ─ AppDelegate ─┬─ AppModel (@Observable) ── NoteStore (load/save JSON, debounced)
                          ├─ NoteWindowManager ── NoteWindow (borderless) ── StickyNoteView
                          ├─ BoardWindow ── BoardView (menu style) ── NoteCard
                          ├─ MainMenu (File / Edit / Format / Window)
                          └─ status-bar item (new note, show board)
```

* `AppModel` is the single entry point for mutations (new / stick / unstick / delete /
  flavour / always-on-top). After any change that affects on-screen state it asks
  `NoteWindowManager.sync()` to open/close windows so the windows always mirror the store.
* A note is edited in exactly one place at a time: on-screen notes are edited in their
  window (clicking them on the board brings the window forward); in-app notes open as a page.
* Format menu items are sent down the responder chain (`target = nil`), so ⌘B/⌘I etc.
  act on whichever note editor has focus. The hover toolbar talks to its own editor
  through a small `EditorController`.

## Sticky note window

```
  ╲══════════════════════════════╱   ← back chopstick (behind the note)
  ┌─══════════════════════════──┐   ← front chopstick (over the note) — drag here to move
  │  text…                       │
  │  ☐ checklist                 │
  │  🦐                          │
  │  B I U S  • ☐          ⋯  ◢  │   ← hover toolbar; folded corner = resize grip
  └──────────────────────────────┘
```

* Borderless, transparent `NSWindow`; the note body, shadow and chopsticks are drawn in SwiftUI.
* **Move**: the top strip (chopsticks + top edge) calls `NSWindow.performDrag`.
* **Resize**: the folded bottom-right corner tracks the mouse in screen space and resizes
  the window with the top edge pinned.
* Frame is persisted on move/resize; restored on launch (and re-homed if the screen is gone).
* `⌘W` on a note puts it back in the board (it is never deleted by closing).

## Visual design

Soft, light palette; each flavour is a noodle with a paper colour, a deeper fold colour and
two accent colours used for small hand-drawn (vector) motifs in the corners and the lacquer
band on the chopsticks.

| Flavour | Paper | Motifs |
| --- | --- | --- |
| Prawn Mee 虾面 | pale coral | curled prawns |
| Ramen ラーメン | butter | naruto swirl, jammy egg |
| Matcha Soba 茶そば | sage | scallion rings |
| Laksa 叻沙 | apricot | tofu puffs, chilli |
| Pho phở | mint | Thai basil, lime wedge |
| Japchae 잡채 | lavender | shiitake, sesame |
| Udon うどん | eggshell | wavy noodles, steam |

Chopsticks: light wood, tapered, with a coloured lacquer band at the thick end matching the
note's flavour. They converge toward the tips, "pinching" the note's top edge.

**Board ("the menu")**: cream menu-paper background, serif masthead (`chopstix` /
NOTES · NOODLES / double rule), filter tabs (everything / on screen / in the menu), then one
section per flavour styled like a menu heading — name, native name, dotted leader, count and
a one-line italic description — followed by a grid of note cards numbered like dishes
(`No. 07`).

Typography: SF Rounded for note text, New York (system serif) for the menu.

## Out of scope for the MVP

Images in notes, sync/iCloud, search, nested lists / indentation, reminders, export.

## Verification

* `scripts/test.sh` — unit tests for the markdown parser and editing logic, legacy conversion and the store.
* `swift run Chopstix --snapshot <dir>` — renders every flavour, the chopsticks, the board and
  the app icon to PNGs for design review without needing screen-recording permission.
