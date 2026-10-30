/**
 * Builds the Marp instance used by both the worker and the main-thread
 * fallback. Kept DOM-free so it can run anywhere.
 */
import { Marp } from '@marp-team/marp-core'
import { CUSTOM_THEME_CSS } from '@/themes'

export interface RenderResult {
  /** one inline-SVG `<svg>` string per slide */
  slides: string[]
  css: string
  /** speaker notes (HTML comments) per slide */
  notes: string[][]
  /** number of slides */
  count: number
}

/**
 * markdown-it plugin that stamps block elements with their source line so the
 * preview can map a click back to the editor.
 */
function sourceLines(md: any) {
  md.core.ruler.push('edi_source_lines', (state: any) => {
    for (const tok of state.tokens) {
      if (tok.map && tok.nesting !== -1 && tok.type !== 'marpit_slide_open' && !tok.hidden) {
        tok.attrSet('data-line', String(tok.map[0]))
      }
    }
  })
}

export function createMarp(): Marp {
  const marp = new Marp({
    inlineSVG: true,
    html: true,
    math: 'katex',
    minifyCSS: false,
  })
  marp.use(sourceLines)
  for (const css of CUSTOM_THEME_CSS) marp.themeSet.add(css)
  return marp
}

export function renderWith(marp: Marp, source: string): RenderResult {
  const { html, css, comments } = marp.render(source, { htmlAsArray: true })
  const slides = html as unknown as string[]
  return { slides, css, notes: comments as string[][], count: slides.length }
}
