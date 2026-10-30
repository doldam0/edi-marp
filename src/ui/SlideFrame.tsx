import { useLayoutEffect, useRef, type MouseEvent } from 'react'

/**
 * Renders one Marp slide inside a Shadow DOM so deck CSS and app CSS never
 * touch. All frames share a single constructed stylesheet per CSS string, so
 * thirty thumbnails cost one parse.
 */
let cached: { css: string; sheet: CSSStyleSheet } | null = null
function sheetFor(css: string): CSSStyleSheet {
  if (!cached || cached.css !== css) {
    const sheet = new CSSStyleSheet()
    sheet.replaceSync(css)
    cached = { css, sheet }
  }
  return cached.sheet
}

const base = new CSSStyleSheet()
base.replaceSync(`
  :host { display: block; contain: content; }
  .marpit { position: relative; }
  .marpit > svg { display: block; width: 100%; height: auto; }
  :host([data-interactive]) [data-line] { cursor: text; }
  :host([data-interactive]) [data-line]:hover { outline: 1.5px dashed color-mix(in srgb, currentColor 40%, transparent); outline-offset: 3px; border-radius: 3px; }
`)

export interface SlideFrameProps {
  html: string
  css: string
  className?: string
  style?: React.CSSProperties
  /** called with the source line of the clicked element */
  onLineClick?: (line: number) => void
  onClick?: () => void
}

export function SlideFrame({ html, css, className, style, onLineClick, onClick }: SlideFrameProps) {
  const hostRef = useRef<HTMLDivElement>(null)
  const rootRef = useRef<ShadowRoot | null>(null)

  useLayoutEffect(() => {
    const host = hostRef.current!
    rootRef.current ??= host.shadowRoot ?? host.attachShadow({ mode: 'open' })
    rootRef.current.adoptedStyleSheets = [base, sheetFor(css)]
  }, [css])

  useLayoutEffect(() => {
    rootRef.current!.innerHTML = `<div class="marpit">${html}</div>`
  }, [html])

  const handleClick = (e: MouseEvent) => {
    onClick?.()
    if (!onLineClick) return
    for (const el of e.nativeEvent.composedPath()) {
      if (el instanceof Element && el.hasAttribute('data-line')) {
        onLineClick(Number(el.getAttribute('data-line')))
        return
      }
    }
  }

  return <div ref={hostRef} className={className} style={style} data-interactive={onLineClick ? '' : undefined} onClick={handleClick} />
}

/** width / height of the deck, read from the first slide's viewBox */
export function aspectOf(slides: string[]): number {
  const m = /viewBox="0 0 (\d+(?:\.\d+)?) (\d+(?:\.\d+)?)"/.exec(slides[0] ?? '')
  return m ? Number(m[1]) / Number(m[2]) : 16 / 9
}
