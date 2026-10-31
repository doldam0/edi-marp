/**
 * EdiMarp rendering engine.
 *
 * Runs inside a hidden WKWebView; Swift calls `EdiEngine.render(source)` and
 * `EdiEngine.exportHtml(source, title)` through `callAsyncJavaScript`. The
 * engine never touches the DOM, so it is a pure function of the markdown.
 */
import { Marp } from '@marp-team/marp-core'
import { CUSTOM_THEME_CSS } from './themes'

export interface RenderResult {
  /** one inline-SVG `<svg>` string per slide */
  slides: string[]
  /** theme CSS shared by all slides */
  css: string
  /** speaker notes (HTML comments) per slide */
  notes: string[][]
  /** slide width / height, from the first slide's viewBox */
  aspect: number
  /** active theme name, as resolved by Marp */
  theme: string
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

function createMarp(extraThemes: string[], inlineSVG: boolean): Marp {
  const marp = new Marp({
    // Inline-SVG mode wraps each slide in an <svg><foreignObject>. That is what
    // the standalone HTML/PDF export wants (it auto-letterboxes and prints as a
    // vector), but WKWebView fails to *paint* centred flex content inside a
    // <foreignObject> on screen — the section background shows and the text does
    // not — so the live preview renders plain <section> HTML instead (see
    // `render` vs `exportHtml`).
    inlineSVG,
    html: true,
    math: 'katex',
    minifyCSS: false,
    // keep unicode emoji as text so macOS draws its own glyphs offline
    emoji: { shortcode: true, unicode: false },
  })
  marp.use(sourceLines)
  for (const css of CUSTOM_THEME_CSS) marp.themeSet.add(css)
  // Workspace themes are registered on top of the built-ins; a later add with
  // the same @theme name overrides an earlier one.
  for (const css of extraThemes) {
    try { marp.themeSet.add(css) } catch { /* a malformed theme file should not break rendering */ }
  }
  return marp
}

// One Marp per distinct (render mode, set of workspace themes), so multiple
// windows with different themes never clash. Keyed by mode + the joined CSS.
const marpCache = new Map<string, Marp>()

function marpFor(extraThemes: string[], inlineSVG: boolean): Marp {
  const key = (inlineSVG ? '1' : '0') + '\u0000' + extraThemes.join('\u0000')
  let marp = marpCache.get(key)
  if (!marp) {
    marp = createMarp(extraThemes, inlineSVG)
    if (marpCache.size > 16) marpCache.clear()
    marpCache.set(key, marp)
  }
  return marp
}

function aspectOf(svg: string | undefined): number {
  const m = svg?.match(/viewBox="0 0 (\d+(?:\.\d+)?) (\d+(?:\.\d+)?)"/)
  return m ? Number(m[1]) / Number(m[2]) : 16 / 9
}

/** HTML mode has no SVG viewBox; the slide box lives on the `section` rule. */
function aspectFromCSS(css: string): number {
  const block = css.match(/>\s*section\s*\{([^}]*)\}/)
  const body = block ? block[1] : ''
  const w = Number(body.match(/\bwidth:\s*([\d.]+)px/)?.[1])
  const h = Number(body.match(/\bheight:\s*([\d.]+)px/)?.[1])
  return w && h ? w / h : 16 / 9
}

export function render(source: string, extraThemes: string[] = []): RenderResult {
  // Live preview: plain <section> HTML (no inline SVG) so WKWebView paints it.
  // The preview shell scales each section to fit its card.
  const marp = marpFor(extraThemes, false)
  const { html, css, comments } = marp.render(source, { htmlAsArray: true })
  const slides = html as unknown as string[]
  const theme = marp.lastGlobalDirectives?.theme ?? 'default'
  return { slides, css, notes: comments as string[][], aspect: aspectFromCSS(css), theme }
}

export function themes(extraThemes: string[] = []): string[] {
  return [...marpFor(extraThemes, false).themeSet.themes()].map((t) => t.name)
}

const escapeHtml = (s: string) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]!))

/**
 * A self-contained HTML deck: Marp CSS + inline-SVG slides + a tiny keyboard
 * navigator. Opens anywhere, prints to PDF with one slide per page.
 */
export function exportHtml(source: string, title: string, extraThemes: string[] = []): string {
  // Export keeps inline SVG: it opens in a browser and prints to PDF, both of
  // which render <foreignObject> correctly and letterbox the slides for free.
  const marp = marpFor(extraThemes, true)
  const { html, css } = marp.render(source, { htmlAsArray: true })
  const slidesArr = html as unknown as string[]
  const r = { slides: slidesArr, css, aspect: aspectOf(slidesArr[0]) }
  const slides = r.slides.map((s, i) => `<div class="slide" data-index="${i}">${s}</div>`).join('\n')
  const [w, h] = r.aspect >= 1 ? [1280, Math.round(1280 / r.aspect)] : [Math.round(720 * r.aspect), 720]
  return `<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<style>${r.css}</style>
<style>
  html, body { margin: 0; background: #111; }
  .deck { display: flex; flex-direction: column; align-items: center; gap: 24px; padding: 24px; }
  .slide { width: min(100%, ${w}px); box-shadow: 0 10px 40px rgba(0,0,0,.4); }
  .slide svg { display: block; width: 100%; height: auto; }
  body.present .deck { padding: 0; gap: 0; height: 100vh; justify-content: center; }
  body.present .slide { display: none; width: 100vw; max-width: calc(100vh * ${r.aspect}); box-shadow: none; }
  body.present .slide.current { display: block; }
  @media print {
    @page { size: ${w}px ${h}px; margin: 0; }
    html, body { background: #fff; }
    .deck { display: block; padding: 0; }
    .slide { width: ${w}px; height: ${h}px; box-shadow: none; page-break-after: always; break-after: page; }
    .slide:last-child { page-break-after: auto; break-after: auto; }
  }
</style>
</head>
<body>
<div class="deck marpit">
${slides}
</div>
<script>
(() => {
  const slides = [...document.querySelectorAll('.slide')];
  let i = 0, present = false;
  const show = (n) => { i = Math.max(0, Math.min(n, slides.length - 1)); slides.forEach((s, k) => s.classList.toggle('current', k === i)); location.hash = String(i + 1); };
  const toggle = () => { present = !present; document.body.classList.toggle('present', present); if (present) show(i); };
  addEventListener('keydown', (e) => {
    if (e.key === 'f' || e.key === 'F') return toggle();
    if (!present) return;
    if (['ArrowRight', ' ', 'PageDown', 'j'].includes(e.key)) show(i + 1);
    if (['ArrowLeft', 'PageUp', 'k'].includes(e.key)) show(i - 1);
    if (e.key === 'Escape') toggle();
  });
  const h = parseInt(location.hash.slice(1), 10);
  if (h) { i = h - 1; }
})();
</script>
</body>
</html>`
}
