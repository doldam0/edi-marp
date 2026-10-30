# edi · marp

A native macOS editor for [Marp](https://marp.app) markdown slide decks, built with
SwiftUI. Write markdown on the left, watch the deck render on the right, and drive
everything with native sidebars, inspectors, menus, and keyboard shortcuts.

The guiding idea: **the markdown is the single source of truth.** Every GUI action —
toggling a directive, switching themes, reordering slides — is a pure
`(Deck) -> [Edit]` transform applied to the text through one undo stack. There is no
hidden slide model to drift out of sync, and ⌘Z reverses any action, GUI or typed.

## Running it

Requires macOS 26+ and Xcode 26+.

```bash
# 1. Build the Marp engine bundle (once, or after changing engine/)
cd engine && npm install && npm run build && cd ..

# 2. Generate the Xcode project (needs xcodegen: `brew install xcodegen`)
xcodegen generate

# 3. Open and run
open EdiMarp.xcodeproj
```

Or build and launch from the command line:

```bash
xcodebuild -project EdiMarp.xcodeproj -scheme EdiMarp -configuration Debug \
  -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/EdiMarp.app
```

## Architecture

```
Packages/EdiCore/       Pure Swift: the parser and the transforms. No UI, fully tested.
  Deck.swift            Parses markdown into slides, directives, line/offset maps.
  Transforms.swift      (Deck, …) -> [Edit] : insert/move/duplicate/delete slides,
                        set global & per-slide directives, toggle classes.
  Edit.swift            A UTF-16 text replacement; [Edit].apply(to:) for tests.

engine/                 TypeScript: @marp-team/marp-core bundled to one IIFE that
                        runs inside a hidden WKWebView. Renders a deck to inline-SVG
                        slides and exports a standalone HTML deck. No network access.

EdiMarp/                The SwiftUI app.
  Document/             DeckDocument (ReferenceFileDocument) + DeckSession, the
                        per-window state that turns transforms into undoable edits.
  Editor/               NSTextView wrapper: markdown syntax highlighting, a gutter
                        that numbers lines and badges slide boundaries.
  Engine/               MarpEngine (the hidden render WebView) and SlideHostView
                        (one slide in its own transparent WebView).
  Views/                NavigationSplitView shell, slide sidebar, focus/grid preview,
                        inspector, presenter, status bar, toolbar.
  Export/               Standalone HTML, vector PDF (one slide per page), print.
```

Three things worth calling out:

- **The markdown is the only state.** `DeckSession.apply` runs a transform and feeds the
  resulting edits to the text view, so a click in the inspector and a keystroke land on
  the same undo stack. Text changes are observed through the text storage, so typing,
  programmatic edits, and undo/redo all reparse and re-render through one path.
- **Cursor and slide stay in sync, both ways.** The slide under the cursor is always the
  one shown; clicking a block in the preview jumps the editor to its source line. A
  markdown-it plugin stamps each block with its line number for the round trip.
- **Rendering is isolated.** Marp runs as JavaScript in a hidden WebView, so a parse error
  never takes down the UI, and each slide is drawn in its own Shadow-DOM-like WebView on a
  transparent background that the native layout letterboxes.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘ ⏎` | New slide below |
| `⌘ ⇧ D` | Duplicate slide |
| `⌘ ⇧ ⌫` | Delete slide |
| `⌘ ⇧ ↑ / ↓` | Move slide up / down |
| `⌥ ⌘ ↑ / ↓` | Previous / next slide |
| `⌘ ⇧ L` / `⌘ ⇧ I` | Toggle `lead` / `invert` class |
| `⌘ 1 / 2 / 3` | Editor · Split · Preview layout |
| `⌥ ⌘ G` | Toggle slide grid |
| `⌥ ⌘ I` | Toggle inspector |
| `⌥ ⌘ P` | Start presenting |
| `⌘ S` · `⌘ ⇧ E` · `⌘ P` | Save · Export HTML · Print |

In the presenter window: arrows / space / `j` `k` `h` `l` to move, `N` for speaker
notes with a next-slide preview, `Esc` to exit.

## Themes

Marp's `default`, `gaia`, and `uncover`, plus two that ship with the app: **paper** (a
serif editorial look) and **noir** (black with a lime accent). Their CSS lives in
`engine/src/themes/`.

## Tests

```bash
cd Packages/EdiCore && swift test     # parser + transforms
```

The app also has an opt-in scripted smoke test that drives a real window through every
slide operation, undo, theme switch, and layout change:
`EDIMARP_DEBUG=/tmp/diag.log EDIMARP_DEBUG_SCRIPT=1 open -n EdiMarp.app`.

## Headless export

```bash
EDIMARP_EXPORT_INPUT=deck.md EDIMARP_EXPORT_OUTPUT=deck.pdf \
  EdiMarp.app/Contents/MacOS/EdiMarp      # .pdf or .html
```

## Not included

- PPTX / Keynote export (HTML and PDF only).
- Image/asset embedding beyond what the markdown references by path.
- Live reload of the engine bundle; rebuild `engine/` after changing it.
