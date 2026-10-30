# edi · marp

A native macOS editor for [Marp](https://marp.app) markdown slide decks, built with
SwiftUI. Open a **workspace folder** holding your deck, theme CSS, and images; write
markdown on the left, watch the deck render on the right, and drive everything with
native sidebars, inspectors, menus, and keyboard shortcuts.

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

On first launch, open a folder as a **workspace** (⌘O) or create one (⌘⇧N). A
workspace is any folder; the app finds the markdown decks and `/* @theme */` CSS files
in it, and resolves image paths relative to it. Access to the folder persists across
launches via a security-scoped bookmark.

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
  Workspace/            Workspace (the folder, its decks, themes, file tree, and the
                        active DeckSession), the security-scoped bookmark, and the
                        ediasset:// scheme handler that serves workspace images.
  Document/             DeckSession: the active deck's parse, render, preview state,
                        and undoable mutations, autosaved to its file.
  Editor/               NSTextView wrapper with markdown and CSS highlighting and a
                        gutter that numbers lines and badges slide boundaries.
  Engine/               MarpEngine (the hidden render WebView) and SlideHostView
                        (one slide in its own transparent WebView).
  Views/                NavigationSplitView shell, sidebar (slides / files), editor
                        pane, focus/grid preview, inspector, presenter, toolbar.
  Export/               Standalone HTML (images inlined), vector PDF, print.
```

Things worth calling out:

- **The markdown is the only state.** `DeckSession.apply` runs a transform and feeds the
  resulting edits to the text view, so a click in the inspector and a keystroke land on
  the same undo stack. Text changes are observed through the text storage, so typing,
  programmatic edits, and undo/redo all reparse and re-render through one path.
- **Cursor and slide stay in sync, both ways.** The slide under the cursor is always the
  one shown; clicking a block in the preview jumps the editor to its source line. A
  markdown-it plugin stamps each block with its line number for the round trip.
- **The editor shows one "current file".** The `</>` and brush buttons jump to the active
  deck and its theme CSS; the file explorer opens any file in the workspace. Each open
  file keeps its own buffer and undo stack, while the preview always tracks the deck.
- **Themes are editable text.** Point the deck at a `/* @theme name */` file in the
  workspace and the brush opens it; editing re-renders the deck live. With a built-in
  theme the brush offers to create an editable custom copy.
- **Rendering is isolated.** Marp runs as JavaScript in a hidden WebView, so a parse error
  never takes down the UI; each slide draws in its own transparent WebView, and images
  are served from the workspace through a private URL scheme.

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
| `⌥ ⌘ 1 / 2` | Edit deck markdown / theme CSS |
| `⌘ 0` | Sidebar: slides / files |
| `⌥ ⌘ P` | Start presenting |
| `⌘ O` · `⌘ ⇧ N` | Open / new workspace |
| `⌘ S` · `⌘ ⇧ E` · `⌘ P` | Save · Export HTML · Print |
| `⌃ ⌘ R` | Reload engine |

In the presenter window: arrows / space / `j` `k` `h` `l` to move, `N` for speaker
notes with a next-slide preview, `Esc` to exit.

## Themes

Marp's `default`, `gaia`, and `uncover`, plus two that ship with the app: **paper** (a
serif editorial look) and **noir** (black with a lime accent); their CSS lives in
`engine/src/themes/`. A workspace can hold its own `/* @theme name */` CSS files, which
appear in the theme menu and can be edited as text with the brush button.

## Tests

```bash
cd Packages/EdiCore && swift test     # parser + transforms
```

The app also has an opt-in scripted smoke test (32 checks) that drives a real window
through every slide operation, undo, theme switch, layout change, the editor's deck /
theme toggle, and the custom-theme flow:

```bash
EDIMARP_DEBUG=/tmp/diag.log EDIMARP_DEBUG_SCRIPT=1 \
  EDIMARP_TEST_WORKSPACE=/path/to/a/workspace \
  EdiMarp.app/Contents/MacOS/EdiMarp -ApplePersistenceIgnoreState YES
```

## Headless export

```bash
EDIMARP_EXPORT_INPUT=deck.md EDIMARP_EXPORT_OUTPUT=deck.pdf \
  EdiMarp.app/Contents/MacOS/EdiMarp      # .pdf or .html
```

Sibling `.css` theme files and relative images in the deck's folder are included;
exported HTML inlines images as data URIs so the file is self-contained.

## Engine live reload

The app watches the engine bundle inside its own `.app` and reloads it on change
(re-rendering open decks). To iterate on the engine without restarting, point Vite's
output at the built app and run it in watch mode:

```bash
cd engine
EDIMARP_OUT_DIR="$(cd ..; pwd)/build/DerivedData/Build/Products/Debug/EdiMarp.app/Contents/Resources" \
  npm run watch
```

(The sandbox lets the app read only its own bundle, so live reload writes there rather
than to the source tree.) `⌃⌘R` reloads the engine manually.

## Not included

- PPTX / Keynote export (HTML and PDF only).
- Recursive workspace scanning for decks and themes (top-level only).
- Automatic asset management beyond serving what the markdown references by path.
