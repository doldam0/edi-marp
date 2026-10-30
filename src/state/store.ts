import { create } from 'zustand'
import { parseDocument, slideAtLine, type MarpDocument } from '@/core/document'
import type { RenderResult } from '@/render/marp'
import { SAMPLE_DECK } from '@/sample'
import { loadDraft } from '@/core/storage'

export type PreviewMode = 'focus' | 'grid'
export type ColorScheme = 'dark' | 'light'

export interface Panels { rail: boolean; editor: boolean; preview: boolean }

export interface AppState {
  source: string
  doc: MarpDocument
  /** editor cursor, 0-based line */
  cursorLine: number
  /** slide the user is "on" – derived from the cursor, or set explicitly */
  activeSlide: number
  render: RenderResult | null
  renderError: string | null
  panels: Panels
  previewMode: PreviewMode
  presenting: boolean
  paletteOpen: boolean
  notesOpen: boolean
  scheme: ColorScheme
  file: { name: string; handle: FileSystemFileHandle | null; dirty: boolean; savedAt: number | null }

  setSource(source: string): void
  setCursorLine(line: number): void
  setActiveSlide(index: number): void
  setRender(r: RenderResult | null, error?: string | null): void
  togglePanel(p: keyof Panels): void
  setPanels(p: Partial<Panels>): void
  setPreviewMode(m: PreviewMode): void
  setPresenting(v: boolean): void
  setPaletteOpen(v: boolean): void
  setNotesOpen(v: boolean): void
  setScheme(s: ColorScheme): void
  setFile(f: Partial<AppState['file']>): void
}

const draft = loadDraft()
const initialSource = draft?.source ?? SAMPLE_DECK
const initialScheme: ColorScheme = (localStorage.getItem('edi:scheme') as ColorScheme) || (matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark')

function readJSON<T>(key: string, fallback: T): T {
  try { return { ...fallback, ...JSON.parse(localStorage.getItem(key) ?? 'null') } } catch { return fallback }
}
const initialLayout = readJSON<{ panels: Panels; previewMode: PreviewMode }>('edi:layout', { panels: { rail: true, editor: true, preview: true }, previewMode: 'focus' })
const persistLayout = (panels: Panels, previewMode: PreviewMode) => localStorage.setItem('edi:layout', JSON.stringify({ panels, previewMode }))

export const useStore = create<AppState>((set, get) => ({
  source: initialSource,
  doc: parseDocument(initialSource),
  cursorLine: 0,
  activeSlide: 0,
  render: null,
  renderError: null,
  panels: initialLayout.panels,
  previewMode: initialLayout.previewMode,
  presenting: false,
  paletteOpen: false,
  notesOpen: false,
  scheme: initialScheme,
  file: { name: draft?.name ?? 'untitled.md', handle: null, dirty: false, savedAt: null },

  setSource(source) {
    if (source === get().source) return
    const doc = parseDocument(source)
    const activeSlide = Math.min(slideAtLine(doc, get().cursorLine), doc.slides.length - 1)
    set({ source, doc, activeSlide, file: { ...get().file, dirty: true } })
  },
  setCursorLine(line) {
    const { doc, cursorLine } = get()
    if (line === cursorLine) return
    set({ cursorLine: line, activeSlide: slideAtLine(doc, line) })
  },
  setActiveSlide(index) {
    const { doc } = get()
    set({ activeSlide: Math.max(0, Math.min(index, doc.slides.length - 1)) })
  },
  setRender(render, error = null) {
    set({ render, renderError: error })
  },
  togglePanel(p) {
    const panels = { ...get().panels, [p]: !get().panels[p] }
    if (!panels.editor && !panels.preview) panels.preview = true
    persistLayout(panels, get().previewMode)
    set({ panels })
  },
  setPanels(p) { const panels = { ...get().panels, ...p }; persistLayout(panels, get().previewMode); set({ panels }) },
  setPreviewMode(previewMode) { persistLayout(get().panels, previewMode); set({ previewMode }) },
  setPresenting(presenting) { set({ presenting }) },
  setPaletteOpen(paletteOpen) { set({ paletteOpen }) },
  setNotesOpen(notesOpen) { set({ notesOpen }) },
  setScheme(scheme) {
    localStorage.setItem('edi:scheme', scheme)
    set({ scheme })
  },
  setFile(f) { set({ file: { ...get().file, ...f } }) },
}))

export const selectActive = (s: AppState) => s.doc.slides[s.activeSlide]
