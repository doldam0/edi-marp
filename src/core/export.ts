import type { RenderResult } from '@/render/marp'

const escapeHtml = (s: string) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]!))

/**
 * A self-contained HTML deck: Marp CSS + inline-SVG slides + a tiny keyboard
 * navigator. Opens anywhere, prints to PDF with one slide per page.
 */
export function buildStandaloneHtml(render: RenderResult, title: string): string {
  const slides = render.slides.map((s, i) => `<div class="slide" data-index="${i}">${s}</div>`).join('\n')
  return `<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<style>${render.css}</style>
<style>
  html, body { margin: 0; background: #111; }
  .deck { display: flex; flex-direction: column; align-items: center; gap: 24px; padding: 24px; }
  .slide { width: min(100%, 1280px); box-shadow: 0 10px 40px rgba(0,0,0,.4); }
  .slide svg { display: block; width: 100%; height: auto; }
  body.present .deck { padding: 0; gap: 0; height: 100vh; justify-content: center; }
  body.present .slide { display: none; width: 100vw; max-width: calc(100vh * var(--ratio, 1.7778)); box-shadow: none; }
  body.present .slide.current { display: block; }
  @media print {
    @page { size: 1280px 720px; margin: 0; }
    html, body { background: #fff; }
    .deck { display: block; padding: 0; }
    .slide { width: 1280px; height: 720px; box-shadow: none; page-break-after: always; break-after: page; }
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
  const first = slides[0]?.querySelector('svg');
  if (first) { const [,, w, h] = (first.getAttribute('viewBox') || '0 0 1280 720').split(' ').map(Number); document.body.style.setProperty('--ratio', String(w / h)); }
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

/** Open the standalone deck in a hidden iframe and trigger the print dialog (→ Save as PDF). */
export function printToPdf(render: RenderResult, title: string) {
  const html = buildStandaloneHtml(render, title)
  const iframe = document.createElement('iframe')
  iframe.style.cssText = 'position:fixed;inset:0;width:0;height:0;border:0;opacity:0;pointer-events:none'
  document.body.appendChild(iframe)
  const doc = iframe.contentDocument!
  doc.open()
  doc.write(html)
  doc.close()
  const win = iframe.contentWindow!
  const cleanup = () => setTimeout(() => iframe.remove(), 500)
  win.addEventListener('afterprint', cleanup)
  setTimeout(() => { win.focus(); win.print() }, 300)
}
