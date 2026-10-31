# markdown notes — plan & design

Companion to [markdown_features.md](markdown_features.md) and [chopstix_design.md](chopstix_design.md).

## What it is

A second kind of note — a **markdown note** — for longer, structured notes. It is written in
plain markdown but renders as you type, so it reads like a finished page while staying a
portable `.md` underneath. It lives everywhere a sticky note does (on the screen held by
chopsticks, or only in the board) and can also be opened as a full **page** for focused
writing, then saved as `.md` or exported as PDF.

The existing rich-text notes are untouched; they are now "sticky notes" in the UI.

## Live rendering ("render on the fly")

The text stays markdown source; the editor styles it and hides the syntax that isn't needed:

| Markdown | Rendered as |
| --- | --- |
| `# ` `## ` `### ` | larger serif headings (menu-board type) |
| `**bold**` `*italic*` `~~strike~~` `==highlight==` `` `code` `` | styled text |
| `[text](url)` | accent-coloured link, ⌘-click to open |
| `- item` / `1. item` | hanging-indented list, bullets drawn as dots |
| `- [ ] task` / `- [x] task` | a drawn checkbox (click to tick); done items fade & strike |
| `> quote` | a lacquer-coloured bar beside faded text |
| ```` ``` ```` fences | monospaced block on a deeper paper tint |
| `---` | a thin rule |

**Syntax fades away off the current line** (like Obsidian's live preview): markers such as
`**`, `#`, `>` and a link's `(url)` are shown faintly on the line with the caret, and are
hidden everywhere else — and everywhere when the note isn't focused. Hiding is done in
TextKit 1 by generating *null glyphs* for those characters, so the text itself never
changes and the caret never moves through invisible characters (the line it is on is
always fully revealed).

Pieces:

* `MarkdownParser` — pure, line-based parser → tokens with `NSRange`s (unit tested).
* `MarkdownStyler` — tokens → attributes, incl. custom `cxHidden` / `cxDecoration` attributes.
  Restyles on every edit inside `processEditing`; only the edited paragraphs are restyled
  unless a code fence changed.
* `MarkdownLayoutManager` — hides syntax glyphs off the active line, draws bullets,
  checkboxes, quote bars, code-block backgrounds and rules.
* `MarkdownEditing` — pure edit logic: list continuation, wrap/unwrap markers, line
  prefixes, indent, ticking tasks (unit tested, reusing `TextEdit`).
* `MarkdownTextView` — the `NSTextView` that wires it together.

## Quality-of-life (borrowed lightly from Notion & friends)

* **`/` menu** on an empty line → heading, list, to-do, quote, code block, divider.
* **Return continues** bullets, numbers (incrementing), to-dos and quotes; Return on an empty
  item outdents it, then ends the list. **Tab / ⇧Tab** nest and un-nest list items.
* **Shortcuts toggle markers**: ⌘B ⌘I ⇧⌘X ⌘E (code) ⇧⌘H (highlight) ⌘K (link),
  ⌥⌘1–3 headings, ⌥⌘0 body text, ⇧⌘7 bullets, ⇧⌘9 numbers, ⇧⌘L to-dos.
* **Paste a URL over selected text** → it becomes a link. Pasted text is always plain.
* Word count & reading time on the page.
* **Convert a sticky note to markdown** (⋯ menu) — bold/italic/strike, bullets and
  checklists carry over.

## Sticky ↔ page

* Sticky markdown notes look like other notes (paper, garnish, chopsticks). Their hover
  toolbar has: heading, bold, italic, bullets, to-do · open as page, return to board, ⋯.
* **Open as Page** (toolbar ⤢, ⌥⌘↩, or clicking an in-menu markdown note on the board)
  opens a normal resizable window — native full screen works — on the note's paper colour,
  with a centred reading column, the dish number & flavour in the header, and a stamp-style
  **save** button.
* A note is still edited in exactly one place: while its page is open the sticky window
  steps aside, and comes back (with the new text) when the page closes.

## Saving & exporting

* **save** (⌘S) writes the note to a `.md` file the user chooses the first time; after that
  ⌘S re-saves to the same file, and the page footer says where and when. **Save As…** (⇧⌘S)
  picks a new file. **Export as PDF…** (⇧⌘E) renders the note exactly as the editor draws it
  (syntax hidden, drawn checkboxes etc.) onto paginated A4/Letter pages.
* Export state (`exportPath`, `exportedAt`) is stored on the note.

## Storage — efficient and reliable

```
~/Library/Application Support/Chopstix/
  notes.json              index: every note's metadata + sticky-note runs (small)
  notes.backup.json       copy of the last notes.json that loaded cleanly (taken at launch)
  markdown/<uuid>.md      one plain .md file per markdown note
```

* **Efficient**: markdown bodies are not in `notes.json`. Typing in a markdown note rewrites
  only that note's `.md` file plus the small index, not every note's text.
* **Reliable**: every write is atomic (write-to-temp + rename). Bodies are written before
  the index, and deleted after it, so the index never points at a missing body. If
  `notes.json` can't be read it is set aside (as before) and the backup is loaded; any `.md`
  body not referenced by the index is adopted back into the board instead of being lost.
  Bodies are plain markdown, readable by any editor even without chopstix.
* Format version bumps to 2; version-1 files load unchanged (no `kind` → sticky note).

## Out of scope

Tables, images, nested quotes, syncing linked files back from disk, search.
