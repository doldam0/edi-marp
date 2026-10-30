import { EditorState, Compartment, RangeSetBuilder, type Extension } from '@codemirror/state'
import { EditorView, keymap, lineNumbers, highlightActiveLine, drawSelection, dropCursor, Decoration, ViewPlugin, type DecorationSet, type ViewUpdate, highlightActiveLineGutter, placeholder } from '@codemirror/view'
import { defaultKeymap, history, historyKeymap, indentWithTab } from '@codemirror/commands'
import { searchKeymap, highlightSelectionMatches } from '@codemirror/search'
import { closeBrackets, closeBracketsKeymap } from '@codemirror/autocomplete'
import { markdown, markdownLanguage } from '@codemirror/lang-markdown'
import { languages } from '@codemirror/language-data'
import { syntaxHighlighting, HighlightStyle, bracketMatching } from '@codemirror/language'
import { tags as t } from '@lezer/highlight'
import { parseDocument } from '@/core/document'

/** Syntax colours ride on CSS variables so the app's scheme toggle applies. */
const highlight = HighlightStyle.define([
  { tag: t.heading, color: 'var(--syn-heading)', fontWeight: '600' },
  { tag: t.heading1, color: 'var(--syn-heading)', fontWeight: '700', fontSize: '1.12em' },
  { tag: t.emphasis, fontStyle: 'italic', color: 'var(--syn-em)' },
  { tag: t.strong, fontWeight: '700', color: 'var(--syn-strong)' },
  { tag: t.link, color: 'var(--syn-link)', textDecoration: 'underline' },
  { tag: t.url, color: 'var(--syn-link)' },
  { tag: t.monospace, color: 'var(--syn-code)' },
  { tag: t.comment, color: 'var(--syn-comment)', fontStyle: 'italic' },
  { tag: t.contentSeparator, color: 'var(--syn-sep)', fontWeight: '700' },
  { tag: t.quote, color: 'var(--syn-quote)' },
  { tag: t.list, color: 'var(--syn-list)' },
  { tag: t.processingInstruction, color: 'var(--syn-punct)' },
  { tag: t.meta, color: 'var(--syn-comment)' },
  { tag: t.keyword, color: 'var(--syn-kw)' },
  { tag: t.string, color: 'var(--syn-str)' },
  { tag: t.number, color: 'var(--syn-num)' },
  { tag: t.typeName, color: 'var(--syn-type)' },
  { tag: t.function(t.variableName), color: 'var(--syn-fn)' },
  { tag: t.propertyName, color: 'var(--syn-prop)' },
])

const theme = EditorView.theme({
  '&': { height: '100%', fontSize: '14px', backgroundColor: 'transparent', color: 'var(--fg)' },
  '.cm-scroller': { fontFamily: 'var(--font-mono)', lineHeight: '1.7', padding: '12px 0 40vh' },
  '.cm-content': { caretColor: 'var(--accent)', padding: '0 20px 0 8px' },
  '.cm-line': { padding: '0 4px' },
  '&.cm-focused': { outline: 'none' },
  '.cm-cursor, .cm-dropCursor': { borderLeftColor: 'var(--accent)', borderLeftWidth: '2px' },
  '&.cm-focused > .cm-scroller > .cm-selectionLayer .cm-selectionBackground, .cm-selectionBackground': { backgroundColor: 'var(--selection) !important' },
  '.cm-activeLine': { backgroundColor: 'var(--line-active)' },
  '.cm-activeLineGutter': { backgroundColor: 'transparent', color: 'var(--fg)' },
  '.cm-gutters': { backgroundColor: 'transparent', color: 'var(--fg-faint)', border: 'none', fontFamily: 'var(--font-mono)', fontSize: '11px' },
  '.cm-lineNumbers .cm-gutterElement': { padding: '0 8px 0 16px', minWidth: '40px' },
  '.cm-matchingBracket': { backgroundColor: 'var(--selection)', outline: 'none' },
  '.cm-selectionMatch': { backgroundColor: 'var(--selection)' },
  '.cm-searchMatch': { backgroundColor: 'color-mix(in oklab, var(--accent) 30%, transparent)' },
  '.cm-panels': { backgroundColor: 'var(--bg-2)', color: 'var(--fg)', borderColor: 'var(--border)' },
  '.cm-panels input, .cm-panels button': { fontFamily: 'var(--font-sans)' },
  '.cm-slide-sep': { color: 'var(--fg-faint)' },
  '.cm-slide-sep::before': {
    content: 'attr(data-slide)', position: 'absolute', right: '12px', fontSize: '10px', letterSpacing: '0.08em',
    textTransform: 'uppercase', color: 'var(--fg-faint)', fontFamily: 'var(--font-sans)', pointerEvents: 'none',
  },
  '.cm-slide-active': { boxShadow: 'inset 2px 0 0 var(--accent)' },
  '.cm-frontmatter': { backgroundColor: 'var(--bg-2)', color: 'var(--fg-muted)' },
})

/**
 * Decorates slide separators with their index and paints an accent bar along
 * the slide under the cursor. Cheap: re-parses with the pure parser on doc or
 * selection changes only.
 */
const slideDecorations = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet
    constructor(view: EditorView) { this.decorations = this.build(view) }
    update(u: ViewUpdate) { if (u.docChanged || u.selectionSet) this.decorations = this.build(u.view) }
    build(view: EditorView) {
      const text = view.state.doc.toString()
      const doc = parseDocument(text)
      const cursorLine = view.state.doc.lineAt(view.state.selection.main.head).number - 1
      const active = doc.slides.findIndex((s) => cursorLine < s.range.to) === -1 ? doc.slides.length - 1 : doc.slides.findIndex((s) => cursorLine < s.range.to)
      const b = new RangeSetBuilder<Decoration>()
      const lines = view.state.doc
      if (doc.frontmatter) {
        for (let l = doc.frontmatter.range.from; l < doc.frontmatter.range.to; l++) b.add(lines.line(l + 1).from, lines.line(l + 1).from, Decoration.line({ class: 'cm-frontmatter' }))
      }
      doc.slides.forEach((s, i) => {
        if (i > 0) {
          const sepLine = lines.line(s.range.from) // separator sits right above
          b.add(sepLine.from, sepLine.from, Decoration.line({ class: 'cm-slide-sep', attributes: { 'data-slide': `slide ${i + 1}` } }))
        }
        if (i === active) {
          for (let l = s.range.from; l < s.range.to; l++) {
            const ln = lines.line(l + 1)
            b.add(ln.from, ln.from, Decoration.line({ class: 'cm-slide-active' }))
          }
        }
      })
      return b.finish()
    }
  },
  { decorations: (v) => v.decorations },
)

export const wrapCompartment = new Compartment()

export interface EditorCallbacks {
  onChange(source: string): void
  onCursor(line: number): void
}

export function createEditorState(doc: string, cb: EditorCallbacks, extra: Extension[] = []): EditorState {
  return EditorState.create({
    doc,
    extensions: [
      lineNumbers(),
      highlightActiveLine(),
      highlightActiveLineGutter(),
      history(),
      drawSelection(),
      dropCursor(),
      bracketMatching(),
      closeBrackets(),
      highlightSelectionMatches(),
      markdown({ base: markdownLanguage, codeLanguages: languages }),
      syntaxHighlighting(highlight),
      theme,
      slideDecorations,
      wrapCompartment.of(EditorView.lineWrapping),
      placeholder('# 제목을 쓰고, --- 로 슬라이드를 나누세요'),
      keymap.of([...closeBracketsKeymap, ...defaultKeymap, ...historyKeymap, ...searchKeymap, indentWithTab]),
      EditorView.updateListener.of((u) => {
        if (u.docChanged) cb.onChange(u.state.doc.toString())
        if (u.selectionSet || u.docChanged) cb.onCursor(u.state.doc.lineAt(u.state.selection.main.head).number - 1)
      }),
      ...extra,
    ],
  })
}
