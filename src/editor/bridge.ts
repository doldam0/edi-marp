/**
 * The one place that knows about the live CodeMirror view. Everything else
 * talks to the document through `Edit[]`, so the editor can be unmounted
 * (panel hidden) and the app keeps working against the store.
 */
import { EditorView } from '@codemirror/view'
import { EditorSelection } from '@codemirror/state'
import { applyEdits as applyToString, type Edit } from '@/core/edits'
import { lineAtOffset, type MarpDocument } from '@/core/document'
import { useStore } from '@/state/store'

let view: EditorView | null = null

export const bridge = {
  attach(v: EditorView) { view = v },
  detach(v: EditorView) { if (view === v) view = null },
  get view() { return view },

  applyEdits(edits: Edit[], { scrollTo }: { scrollTo?: number } = {}) {
    if (!edits.length) return
    if (view) {
      const changes = edits.map((e) => ({ from: e.from, to: e.to, insert: e.insert }))
      const tr = view.state.update({ changes, scrollIntoView: true, userEvent: 'edi.transform' })
      view.dispatch(tr)
      if (scrollTo !== undefined) bridge.goToOffset(tr.changes.mapPos(scrollTo, 1))
    } else {
      const { source, setSource, setCursorLine } = useStore.getState()
      setSource(applyToString(source, edits))
      if (scrollTo !== undefined) setCursorLine(lineAtOffset(useStore.getState().doc, scrollTo))
    }
  },

  /** Run a transform against the current document and apply what it returns. */
  transform(fn: (doc: MarpDocument) => Edit[], opts?: { scrollTo?: number }) {
    bridge.applyEdits(fn(useStore.getState().doc), opts)
  },

  goToOffset(offset: number, { focus = true } = {}) {
    if (!view) {
      useStore.getState().setCursorLine(lineAtOffset(useStore.getState().doc, offset))
      return
    }
    const pos = Math.max(0, Math.min(offset, view.state.doc.length))
    view.dispatch({ selection: EditorSelection.cursor(pos), effects: EditorView.scrollIntoView(pos, { y: 'center' }) })
    if (focus) view.focus()
  },

  goToLine(line: number, opts?: { focus?: boolean }) {
    const doc = useStore.getState().doc
    const l = Math.max(0, Math.min(line, doc.lines.length - 1))
    bridge.goToOffset(doc.offsets[l], opts)
  },

  /** Jump to the first content line of a slide. */
  goToSlide(index: number, opts?: { focus?: boolean }) {
    const { doc, setActiveSlide } = useStore.getState()
    const slide = doc.slides[index]
    if (!slide) return
    let line = slide.range.from
    while (line < slide.range.to - 1 && doc.lines[line].trim() === '') line++
    setActiveSlide(index)
    bridge.goToLine(line, opts)
  },

  insertAtCursor(text: string) {
    if (!view) return bridge.applyEdits([{ from: useStore.getState().source.length, to: useStore.getState().source.length, insert: text }])
    const { from, to } = view.state.selection.main
    view.dispatch({ changes: { from, to, insert: text }, selection: EditorSelection.cursor(from + text.length), scrollIntoView: true })
    view.focus()
  },

  focus() { view?.focus() },
}
